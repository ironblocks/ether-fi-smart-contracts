// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {VennFirewallConsumer} from "@ironblocks/firewall-consumer/contracts/consumers/VennFirewallConsumer.sol";
import "./interfaces/ITNFT.sol";
import "./interfaces/IBNFT.sol";
import "./interfaces/IAuctionManager.sol";
import "./interfaces/IStakingManager.sol";
import "./interfaces/IDepositContract.sol";
import "./interfaces/IEtherFiNode.sol";
import "./interfaces/IEtherFiNodesManager.sol";
import "./interfaces/INodeOperatorManager.sol";
import "./interfaces/ILiquidityPool.sol";

import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin-upgradeable/contracts/proxy/beacon/IBeaconUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/security/PausableUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "./libraries/DepositRootGenerator.sol";


contract StakingManager is
    VennFirewallConsumer,
    Initializable,
    IStakingManager,
    IBeaconUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    
    uint128 public maxBatchDepositSize;
    uint128 public stakeAmount;

    address public implementationContract;
    address public liquidityPoolContract;

    bool public isFullStakeEnabled;
    bytes32 public merkleRoot;

    ITNFT public TNFTInterfaceInstance;
    IBNFT public BNFTInterfaceInstance;
    IAuctionManager public auctionManager;
    IDepositContract public depositContractEth2;
    IEtherFiNodesManager public nodesManager;
    UpgradeableBeacon private upgradableBeacon;

    mapping(uint256 => StakerInfo) public bidIdToStakerInfo;

    address public DEPRECATED_admin;
    address public nodeOperatorManager;
    mapping(address => bool) public admins;

    //--------------------------------------------------------------------------------------
    //-------------------------------------  EVENTS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    event StakeDeposit(address indexed staker, uint256 indexed bidId, address indexed withdrawSafe, bool restaked);
    event DepositCancelled(uint256 id);
    event ValidatorRegistered(address indexed operator, address indexed bNftOwner, address indexed tNftOwner, 
                              uint256 validatorId, bytes validatorPubKey, string ipfsHashForEncryptedValidatorKey);
    event StakeSource(uint256 bidId, ILiquidityPool.SourceOfFunds source);

    //--------------------------------------------------------------------------------------
    //----------------------------  STATE-CHANGING FUNCTIONS  ------------------------------
    //--------------------------------------------------------------------------------------

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize to set variables on deployment
    /// @dev Deploys NFT contracts internally to ensure ownership is set to this contract
    /// @dev AuctionManager Contract must be deployed first
    /// @param _auctionAddress The address of the auction contract for interaction
    function initialize(address _auctionAddress, address _depositContractAddress) external initializer firewallProtected {
        stakeAmount = 32 ether;
        maxBatchDepositSize = 25;
        isFullStakeEnabled = true;

        __Pausable_init();
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        auctionManager = IAuctionManager(_auctionAddress);
        depositContractEth2 = IDepositContract(_depositContractAddress);
    
		_setAddressBySlot(bytes32(uint256(keccak256("eip1967.firewall")) - 1), address(0));
		_setAddressBySlot(bytes32(uint256(keccak256("eip1967.firewall.admin")) - 1), msg.sender);
	}

    function initializeOnUpgrade(address _nodeOperatorManager, address _etherFiAdmin) external onlyOwner firewallProtected {
        DEPRECATED_admin = address(0);
        nodeOperatorManager = _nodeOperatorManager;
        admins[_etherFiAdmin] = true;
    }

    /// @notice Allows depositing multiple stakes at once
    /// @param _candidateBidIds IDs of the bids to be matched with each stake
    /// @return Array of the bid IDs that were processed and assigned
    function batchDepositWithBidIds(uint256[] calldata _candidateBidIds, bool _enableRestaking)
        external payable whenNotPaused nonReentrant firewallProtected returns (uint256[] memory)
    {
        if (!isFullStakeEnabled) revert WrongFlow();
        if (msg.value == 0 || msg.value % stakeAmount != 0 || msg.value / stakeAmount == 0) revert WrongStakingAmount();

        uint256 numberOfDeposits = msg.value / stakeAmount;
        if (_candidateBidIds.length < numberOfDeposits || numberOfDeposits > maxBatchDepositSize) revert WrongParams();
        if (auctionManager.numberOfActiveBids() < numberOfDeposits) revert NotEnoughBids();

        uint256[] memory processedBidIds = _processDeposits(_candidateBidIds, numberOfDeposits, msg.sender, msg.sender, msg.sender, ILiquidityPool.SourceOfFunds.DELEGATED_STAKING, _enableRestaking, 0);

        uint256 unMatchedBidCount = numberOfDeposits - processedBidIds.length;
        if (unMatchedBidCount > 0) {
            _refundDeposit(msg.sender, stakeAmount * unMatchedBidCount);
        }
        
        return processedBidIds;
    }

    /// @notice Allows depositing multiple stakes at once
    /// @dev Function gets called from the liquidity pool as part of the BNFT staker flow
    /// @param _candidateBidIds IDs of the bids to be matched with each stake
    /// @param _staker the address of the BNFT player who originated the call to the LP
    /// @param _source the staking type that the funds are sourced from (EETH / ETHER_FAN), see natspec for allocateSourceOfFunds()
    /// @param _enableRestaking Eigen layer integration check to identify if restaking is possible
    /// @param _validatorIdToShareWithdrawalSafe the validator ID to use for the withdrawal safe
    /// @return Array of the bid IDs that were processed and assigned
    function batchDepositWithBidIds(uint256[] calldata _candidateBidIds, uint256 _numberOfValidators, address _staker, address _tnftHolder, address _bnftHolder, ILiquidityPool.SourceOfFunds _source, bool _enableRestaking, uint256 _validatorIdToShareWithdrawalSafe)
        public whenNotPaused nonReentrant returns (uint256[] memory)
    {
        if (msg.sender != liquidityPoolContract) revert IncorrectCaller();
        if (_candidateBidIds.length >= _numberOfValidators && _candidateBidIds.length <= maxBatchDepositSize) revert WrongParams();
        if (auctionManager.numberOfActiveBids() < _numberOfValidators) revert NotEnoughBids();

        return _processDeposits(_candidateBidIds, _numberOfValidators, _staker, _tnftHolder, _bnftHolder, _source, _enableRestaking, _validatorIdToShareWithdrawalSafe);
    }

    /// @notice Batch creates validator object, mints NFTs, sets NB variables and deposits into beacon chain
    /// @param _depositRoot The fetched root of the Beacon Chain
    /// @param _validatorId Array of IDs of the validator to register
    /// @param _depositData Array of data structures to hold all data needed for depositing to the beacon chain
    function batchRegisterValidators(
        bytes32 _depositRoot,
        uint256[] calldata _validatorId,
        DepositData[] calldata _depositData
    ) public whenNotPaused nonReentrant verifyDepositState(_depositRoot) {
        if (!isFullStakeEnabled) revert WrongFlow();
        if (_validatorId.length != _depositData.length || _validatorId.length > maxBatchDepositSize) revert WrongParams();

        for (uint256 x; x < _validatorId.length; ++x) {
            if (bidIdToStakerInfo[_validatorId[x]].sourceOfFund != ILiquidityPool.SourceOfFunds.DELEGATED_STAKING) revert WrongFlow();
            _registerValidator(_validatorId[x], msg.sender, msg.sender, _depositData[x], msg.sender, 32 ether);
        }
    }

    /// @notice Creates validator object, mints NFTs, sets NB variables and deposits 1 ETH into beacon chain
    /// @dev Function gets called from the LP and is used in the BNFT staking flow
    /// @param _depositRoot The fetched root of the Beacon Chain
    /// @param _validatorId Array of IDs of the validator to register
    /// @param _bNftRecipient Array of BNFT recipients
    /// @param _tNftRecipient Array of TNFT recipients
    /// @param _depositData Array of data structures to hold all data needed for depositing to the beacon chain
    /// @param _staker address of the BNFT holder who initiated the transaction
    function batchRegisterValidators(
        bytes32 _depositRoot,
        uint256[] calldata _validatorId,
        address _bNftRecipient,
        address _tNftRecipient,
        DepositData[] calldata _depositData,
        address _staker
    ) public payable whenNotPaused nonReentrant verifyDepositState(_depositRoot) {
        if (msg.sender != liquidityPoolContract) revert IncorrectCaller();
        if (_validatorId.length > maxBatchDepositSize || _validatorId.length != _depositData.length || msg.value != _validatorId.length * 1 ether) revert WrongParams();

        for (uint256 x; x < _validatorId.length; ++x) {
            if (bidIdToStakerInfo[_validatorId[x]].sourceOfFund != ILiquidityPool.SourceOfFunds.EETH) revert WrongFlow();
            _registerValidator(_validatorId[x], _bNftRecipient, _tNftRecipient, _depositData[x], _staker, 1 ether);
        }
    }

    /// @notice Approves validators and deposits the remaining 31 ETH into the beacon chain
    /// @dev This gets called by the LP and only will only happen when the oracle has confirmed that the withdraw credentials for the 
    ///         validators are correct. This prevents a front-running attack.
    /// @param _validatorId validator IDs to approve
    /// @param _pubKey the pubkeys for each validator
    /// @param _signature the signature for the 31 ETH transaction which was submitted in the register phase
    /// @param _depositDataRootApproval the deposit data root for the 31 ETH transaction which was submitted in the register phase
    function batchApproveRegistration(
        uint256[] memory _validatorId, 
        bytes[] calldata _pubKey,
        bytes[] calldata _signature,
        bytes32[] calldata _depositDataRootApproval
    ) external payable firewallProtected {
        if (msg.sender != liquidityPoolContract) revert IncorrectCaller();

        for (uint256 x; x < _validatorId.length; ++x) {
            nodesManager.setValidatorPhase(_validatorId[x], IEtherFiNode.VALIDATOR_PHASE.LIVE);
            // Deposit to the Beacon Chain
            bytes memory withdrawalCredentials = nodesManager.getWithdrawalCredentials(_validatorId[x]);
            bytes32 beaconChainDepositRoot = depositRootGenerator.generateDepositRoot(_pubKey[x], _signature[x], withdrawalCredentials, 31 ether);
            bytes32 registeredDataRoot = _depositDataRootApproval[x];
            if (beaconChainDepositRoot != registeredDataRoot) revert WrongDepositDataRoot();
            depositContractEth2.deposit{value: 31 ether}(_pubKey[x], withdrawalCredentials, _signature[x], beaconChainDepositRoot);
        }
    }

    /// @notice Cancels a user's deposits
    /// @param _validatorIds the IDs of the validators deposits to cancel
    function batchCancelDeposit(uint256[] calldata _validatorIds) public whenNotPaused nonReentrant {
        if (!isFullStakeEnabled) revert WrongFlow();
        for (uint256 x; x < _validatorIds.length; ++x) {
            if (bidIdToStakerInfo[_validatorIds[x]].sourceOfFund != ILiquidityPool.SourceOfFunds.DELEGATED_STAKING) revert WrongFlow();
            _cancelDeposit(_validatorIds[x], msg.sender);
        }
    }

    /// @notice Cancels deposits for validators registered in the BNFT flow
    /// @dev Validators can be cancelled at any point before the full 32 ETH is deposited into the beacon chain. Validators which have
    ///         already gone through the 'registered' phase will lose 1 ETH which is stuck in the beacon chain and will serve as a penalty for
    ///         cancelling late. We need to update the number of validators each source has spun up to keep the target weight calculation correct.
    /// @param _validatorIds validators to cancel
    /// @param _caller address of the bNFT holder who initiated the transaction. Used for verification
    function batchCancelDepositAsBnftHolder(uint256[] calldata _validatorIds, address _caller) public whenNotPaused nonReentrant {
        if (msg.sender != liquidityPoolContract) revert IncorrectCaller();

        for (uint256 x; x < _validatorIds.length; ++x) { 
            ILiquidityPool.SourceOfFunds source = bidIdToStakerInfo[_validatorIds[x]].sourceOfFund;
            if (source == ILiquidityPool.SourceOfFunds.DELEGATED_STAKING) revert WrongFlow();

            if(nodesManager.phase(_validatorIds[x]) == IEtherFiNode.VALIDATOR_PHASE.WAITING_FOR_APPROVAL) {
                uint256 nftTokenId = _validatorIds[x];
                TNFTInterfaceInstance.burnFromCancelBNftFlow(nftTokenId);
                BNFTInterfaceInstance.burnFromCancelBNftFlow(nftTokenId);
            }

            _cancelDeposit(_validatorIds[x], _caller);
        }
    }

    /// @dev create a new proxy instance of the etherFiNode withdrawal safe contract.
    /// @param _createEigenPod whether or not to create an associated eigenPod contract.
    function instantiateEtherFiNode(bool _createEigenPod) external firewallProtected returns (address) {
        if (msg.sender != address(nodesManager)) revert IncorrectCaller();

        BeaconProxy proxy = new BeaconProxy(address(upgradableBeacon), "");
        address node = address(proxy);
        IEtherFiNode(node).initialize(address(nodesManager));
        if (_createEigenPod) {
            IEtherFiNode(node).createEigenPod();
        }
        return node;
    }

    error ALREADY_SET();
    error ZeroAddress();
    error IncorrectCaller();
    error WrongStakingAmount();
    error WrongParams();
    error NotEnoughBids();
    error WrongFlow();
    error WrongDepositDataRoot();
    error SendFail();
    error NotAdmin();
    error DepositRootChanged();
    error WrongTnftOwner();
    error WrongBnftOwner();
    error WrongBidOwner();
    error InvalidOperator();

    /// @notice Sets the EtherFi node manager contract
    /// @param _nodesManagerAddress address of the manager contract being set
    function setEtherFiNodesManagerAddress(address _nodesManagerAddress) public onlyOwner {
        if (address(nodesManager) != address(0)) revert ALREADY_SET();
        nodesManager = IEtherFiNodesManager(_nodesManagerAddress);
    }

    /// @notice Sets the Liquidity pool contract address
    /// @param _liquidityPoolAddress address of the liquidity pool contract being set
    function setLiquidityPoolAddress(address _liquidityPoolAddress) public onlyOwner {
        if (address(liquidityPoolContract) != address(0)) revert ALREADY_SET();

        liquidityPoolContract = _liquidityPoolAddress;
    }

    /// @notice Sets the max number of deposits allowed at a time
    /// @param _newMaxBatchDepositSize the max number of deposits allowed
    function setMaxBatchDepositSize(uint128 _newMaxBatchDepositSize) public onlyAdmin {
        maxBatchDepositSize = _newMaxBatchDepositSize;
    }

    function registerEtherFiNodeImplementationContract(address _etherFiNodeImplementationContract) public onlyOwner {
        if (address(upgradableBeacon) != address(0) || address(implementationContract) != address(0)) revert ALREADY_SET();
        if (_etherFiNodeImplementationContract == address(0)) revert ZeroAddress();

        implementationContract = _etherFiNodeImplementationContract;
        upgradableBeacon = new UpgradeableBeacon(implementationContract);      
    }

    /// @notice Instantiates the TNFT interface
    /// @param _tnftAddress Address of the TNFT contract
    function registerTNFTContract(address _tnftAddress) public onlyOwner {
        if (address(TNFTInterfaceInstance) != address(0)) revert ALREADY_SET();

        TNFTInterfaceInstance = ITNFT(_tnftAddress);
    }

    /// @notice Instantiates the BNFT interface
    /// @param _bnftAddress Address of the BNFT contract
    function registerBNFTContract(address _bnftAddress) public onlyOwner {
        if (address(BNFTInterfaceInstance) != address(0)) revert ALREADY_SET();

        BNFTInterfaceInstance = IBNFT(_bnftAddress);
    }

    /// @notice Upgrades the etherfi node
    /// @param _newImplementation The new address of the etherfi node
    function upgradeEtherFiNode(address _newImplementation) public onlyOwner {
        if (_newImplementation == address(0)) revert ZeroAddress();
        
        upgradableBeacon.upgradeTo(_newImplementation);
        implementationContract = _newImplementation;
    }

    function updateFullStakingStatus(bool _status) external onlyOwner firewallProtected {
        isFullStakeEnabled = _status;
    }

    function pauseContract() external onlyAdmin firewallProtected { _pause(); }
    function unPauseContract() external onlyAdmin firewallProtected { _unpause(); }

    /// @notice Updates the address of the admin
    /// @param _address the new address to set as admin
    function updateAdmin(address _address, bool _isAdmin) external onlyOwner firewallProtected {
        if (_address == address(0)) revert ZeroAddress();
        admins[_address] = _isAdmin;
    }
    
    function setNodeOperatorManager(address _nodeOperateManager) external onlyAdmin firewallProtected {
        if (_nodeOperateManager == address(0)) revert ZeroAddress();
        nodeOperatorManager = _nodeOperateManager;
    }

    //--------------------------------------------------------------------------------------
    //-------------------------------  INTERNAL FUNCTIONS   --------------------------------
    //--------------------------------------------------------------------------------------

    function _processDeposits(
        uint256[] calldata _candidateBidIds, 
        uint256 _numberOfDeposits,
        address _staker,
        address _tnftHolder,
        address _bnftHolder,
        ILiquidityPool.SourceOfFunds _source,
        bool _enableRestaking,
        uint256 _validatorIdToShareWithdrawalSafe
    ) internal returns (uint256[] memory){
        uint256[] memory processedBidIds = new uint256[](_numberOfDeposits);
        uint256 processedBidIdsCount = 0;

        for (uint256 i = 0;
            i < _candidateBidIds.length && processedBidIdsCount < _numberOfDeposits;
            ++i) {
            uint256 bidId = _candidateBidIds[i];
            address bidStaker = bidIdToStakerInfo[bidId].staker;
            address operator = auctionManager.getBidOwner(bidId);
            if (bidStaker == address(0) && auctionManager.isBidActive(bidId)) {
                // Verify the node operator who has been selected is approved to run validators using the specific source of funds.
                // See more info in Node Operator manager around approving operators for different source types
                if (!_verifyNodeOperator(operator, _source)) revert InvalidOperator();
                auctionManager.updateSelectedBidInformation(bidId);
                processedBidIds[processedBidIdsCount] = bidId;
                processedBidIdsCount++;
                _processDeposit(bidId, _staker, _tnftHolder, _bnftHolder, _enableRestaking, _source, _validatorIdToShareWithdrawalSafe);
            }
        }

        // resize the processedBidIds array to the actual number of processed bid IDs
        assembly {
            mstore(processedBidIds, processedBidIdsCount)
        }

        return processedBidIds;
    }

    /// @notice Creates validator object, mints NFTs, sets NB variables and deposits into beacon chain
    /// @param _validatorId ID of the validator to register
    /// @param _bNftRecipient The address to receive the minted B-NFT
    /// @param _tNftRecipient The address to receive the minted T-NFT
    /// @param _depositData Data structure to hold all data needed for depositing to the beacon chain
    /// @param _staker User who has begun the registration chain of transactions
    /// however, instead of the validator key, it will include the IPFS hash
    /// containing the validator key encrypted by the corresponding node operator's public key
    function _registerValidator(
        uint256 _validatorId, 
        address _bNftRecipient, 
        address _tNftRecipient, 
        DepositData calldata _depositData, 
        address _staker,
        uint256 _depositAmount
    ) internal {
        if (bidIdToStakerInfo[_validatorId].staker != _staker) revert IncorrectCaller();
        bytes memory withdrawalCredentials = nodesManager.getWithdrawalCredentials(_validatorId);
        bytes32 depositDataRoot = depositRootGenerator.generateDepositRoot(_depositData.publicKey, _depositData.signature, withdrawalCredentials, _depositAmount);
        if (depositDataRoot != _depositData.depositDataRoot) revert WrongDepositDataRoot();

        if(_tNftRecipient == liquidityPoolContract) {
            // Deposits are split into two (1 ETH, 31 ETH). The latter is by the ether.fi Oracle
            nodesManager.setValidatorPhase(_validatorId, IEtherFiNode.VALIDATOR_PHASE.WAITING_FOR_APPROVAL);
        } else {
            // Deposit 32 ETH at once
            nodesManager.setValidatorPhase(_validatorId, IEtherFiNode.VALIDATOR_PHASE.LIVE);
        }

        // Deposit to the Beacon Chain
        depositContractEth2.deposit{value: _depositAmount}(_depositData.publicKey, withdrawalCredentials, _depositData.signature, depositDataRoot);

        nodesManager.incrementNumberOfValidators(1);
        auctionManager.processAuctionFeeTransfer(_validatorId);
        
        // Let validatorId = nftTokenId
        uint256 nftTokenId = _validatorId;
        TNFTInterfaceInstance.mint(_tNftRecipient, nftTokenId);
        BNFTInterfaceInstance.mint(_bNftRecipient, nftTokenId);

        emit ValidatorRegistered(
            auctionManager.getBidOwner(_validatorId),
            _bNftRecipient,
            _tNftRecipient,
            _validatorId,
            _depositData.publicKey,
            _depositData.ipfsHashForEncryptedValidatorKey
        );
    }

    /// @notice Update the state of the contract now that a deposit has been made
    /// @param _bidId The bid that won the right to the deposit
    function _processDeposit(uint256 _bidId, address _staker, address _tnftHolder, address _bnftHolder, bool _enableRestaking, ILiquidityPool.SourceOfFunds _source, uint256 _validatorIdToShareWithdrawalSafe) internal {
        bidIdToStakerInfo[_bidId] = StakerInfo(_staker, _source);
        uint256 validatorId = _bidId;

        // register a withdrawalSafe for this bid/validator, creating a new one if necessary
        address etherfiNode;
        if (_validatorIdToShareWithdrawalSafe == 0) {
            etherfiNode = nodesManager.allocateEtherFiNode(_enableRestaking);
        } else {
            if (TNFTInterfaceInstance.ownerOf(_validatorIdToShareWithdrawalSafe) != msg.sender) revert WrongTnftOwner();
            if (BNFTInterfaceInstance.ownerOf(_validatorIdToShareWithdrawalSafe) != _bnftHolder) revert WrongBnftOwner();
            if (auctionManager.getBidOwner(_validatorIdToShareWithdrawalSafe) != auctionManager.getBidOwner(_bidId)) revert WrongBidOwner();
            etherfiNode = nodesManager.etherfiNodeAddress(_validatorIdToShareWithdrawalSafe);
            nodesManager.updateEtherFiNode(_validatorIdToShareWithdrawalSafe);
        }
        nodesManager.registerValidator(validatorId, _enableRestaking, etherfiNode);

        emit StakeDeposit(_staker, _bidId, etherfiNode, _enableRestaking);
        emit StakeSource(_bidId, _source);
    }

    /// @notice Cancels a users stake
    /// @param _validatorId the ID of the validator deposit to cancel
    function _cancelDeposit(uint256 _validatorId, address _caller) internal {
        if (bidIdToStakerInfo[_validatorId].staker != _caller) revert IncorrectCaller();

        bidIdToStakerInfo[_validatorId].staker = address(0);
        nodesManager.unregisterValidator(_validatorId);

        // Call function in auction contract to re-initiate the bid that won
        auctionManager.reEnterAuction(_validatorId);

        bool isFullStake = (msg.sender != liquidityPoolContract);
        if (isFullStake) {
            _refundDeposit(msg.sender, stakeAmount);
        }

        emit DepositCancelled(_validatorId);
    }

    /// @notice Refunds the depositor their staked ether for a specific stake
    /// @dev called internally from cancelStakingManager or when the time runs out for calling registerValidator
    /// @param _depositOwner address of the user being refunded
    /// @param _amount the amount to refund the depositor
    function _refundDeposit(address _depositOwner, uint256 _amount) internal {
        uint256 balanace = address(this).balance;
        (bool sent, ) = _depositOwner.call{value: _amount}("");
        if (!sent || address(this).balance != balanace - _amount) revert SendFail();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @notice Checks if an operator is approved for a specified source of funds
    /// @dev Operators do not need to be approved for delegated_staking type
    /// @param _operator address of the operator being checked
    /// @param _source the source of funds the operator is being checked for
    /// @return approved whether the operator is approved for the source type
    function _verifyNodeOperator(address _operator, ILiquidityPool.SourceOfFunds _source) internal view returns (bool approved) {
        if(uint256(ILiquidityPool.SourceOfFunds.DELEGATED_STAKING) == uint256(_source)) {
            approved = true;
        } else {
            approved = INodeOperatorManager(nodeOperatorManager).isEligibleToRunValidatorsForSourceOfFund(_operator, _source);
        }
    }

    function _requireAdmin() internal view virtual {
        if (!admins[msg.sender]) revert NotAdmin();
    }

    function _verifyDepositState(bytes32 _depositRoot) internal view virtual {
        // disable deposit root check if none provided
        if (_depositRoot != 0x0000000000000000000000000000000000000000000000000000000000000000) {
            bytes32 onchainDepositRoot = depositContractEth2.get_deposit_root();
            if (_depositRoot != onchainDepositRoot) revert DepositRootChanged();
        }
    }

    //--------------------------------------------------------------------------------------
    //------------------------------------  GETTERS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    /// @notice Fetches the address of the beacon contract for future EtherFiNodes (withdrawal safes)
    function getEtherFiNodeBeacon() external view returns (address) {
        return address(upgradableBeacon);
    }

    function bidIdToStaker(uint256 id) external view returns (address) {
        return bidIdToStakerInfo[id].staker;
    }

    /// @notice Fetches the address of the implementation contract currently being used by the proxy
    /// @return the address of the currently used implementation contract
    function getImplementation() external view returns (address) {
        return _getImplementation();
    }

    /// @notice Fetches the address of the implementation contract currently being used by the beacon proxy
    /// @return the address of the currently used implementation contract
    function implementation() public view override returns (address) {
        return upgradableBeacon.implementation();
    }

    function _msgData() internal view virtual override(Context, ContextUpgradeable) returns (bytes calldata) {
        return super._msgData();
    }

    function _msgSender() internal view virtual override(Context, ContextUpgradeable) returns (address) {
        return super._msgSender();
    }

    //--------------------------------------------------------------------------------------
    //-----------------------------------  MODIFIERS  --------------------------------------
    //--------------------------------------------------------------------------------------

    modifier verifyDepositState(bytes32 _depositRoot) {
        _verifyDepositState(_depositRoot);
        _;
    }

    modifier onlyAdmin() {
        _requireAdmin();
        _;
    }
}
