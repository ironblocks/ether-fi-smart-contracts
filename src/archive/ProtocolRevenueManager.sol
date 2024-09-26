// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {VennFirewallConsumer} from "@ironblocks/firewall-consumer/contracts/consumers/VennFirewallConsumer.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/security/PausableUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "../interfaces/IProtocolRevenueManager.sol";
import "../interfaces/IEtherFiNodesManager.sol";
import "../interfaces/IAuctionManager.sol";

contract ProtocolRevenueManager is
    VennFirewallConsumer,
    Initializable,
    IProtocolRevenueManager,
    PausableUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    //--------------------------------------------------------------------------------------
    //---------------------------------  STATE-VARIABLES  ----------------------------------
    //--------------------------------------------------------------------------------------
    
    IEtherFiNodesManager public etherFiNodesManager;
    IAuctionManager public auctionManager;

    uint256 public DEPRECATED_globalRevenueIndex;
    uint128 public DEPRECATED_vestedAuctionFeeSplitForStakers;
    uint128 public DEPRECATED_auctionFeeVestingPeriodForStakersInDays;

    address public admin;

    //--------------------------------------------------------------------------------------
    //----------------------------  STATE-CHANGING FUNCTIONS  ------------------------------
    //--------------------------------------------------------------------------------------
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer firewallProtected {
        __Pausable_init();
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        DEPRECATED_globalRevenueIndex = 1;
        DEPRECATED_vestedAuctionFeeSplitForStakers = 50; // 50% of the auction fee is vested
        DEPRECATED_auctionFeeVestingPeriodForStakersInDays = 6 * 7 * 4; // 6 months
    
		_setAddressBySlot(bytes32(uint256(keccak256("eip1967.firewall")) - 1), address(0));
		_setAddressBySlot(bytes32(uint256(keccak256("eip1967.firewall.admin")) - 1), msg.sender);
	}


    //--------------------------------------------------------------------------------------
    //-----------------------------------  SETTERS   ---------------------------------------
    //--------------------------------------------------------------------------------------

    /// @notice Instantiates the interface of the node manager for integration
    /// @dev Set manually due to circular dependencies
    /// @param _etherFiNodesManager etherfi node manager address to set
    function setEtherFiNodesManagerAddress(address _etherFiNodesManager) external onlyOwner firewallProtected {
        require(_etherFiNodesManager != address(0), "No zero addresses");
        require(address(etherFiNodesManager) == address(0), "Address already set");
        etherFiNodesManager = IEtherFiNodesManager(_etherFiNodesManager);
    }

    /// @notice Instantiates the interface of the auction manager for integration
    /// @dev Set manually due to circular dependencies
    /// @param _auctionManager auction manager address to set
    function setAuctionManagerAddress(address _auctionManager) external onlyOwner firewallProtected {
        require(_auctionManager != address(0), "No zero addresses");
        require(address(auctionManager) == address(0), "Address already set");
        auctionManager = IAuctionManager(_auctionManager);
    }

    function pauseContract() external onlyAdmin firewallProtected { _pause(); }
    function unPauseContract() external onlyAdmin firewallProtected { _unpause(); }

    /// @notice Updates the address of the admin
    /// @param _newAdmin the new address to set as admin
    function updateAdmin(address _newAdmin) external onlyOwner firewallProtected {
        require(_newAdmin != address(0), "Cannot be address zero");
        admin = _newAdmin;
    }

    //--------------------------------------------------------------------------------------
    //-------------------------------  INTERNAL FUNCTIONS   --------------------------------
    //--------------------------------------------------------------------------------------

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function _msgData() internal view virtual override(Context, ContextUpgradeable) returns (bytes calldata) {
        return super._msgData();
    }

    function _msgSender() internal view virtual override(Context, ContextUpgradeable) returns (address) {
        return super._msgSender();
    }
    
    //--------------------------------------------------------------------------------------
    //-------------------------------------  GETTER   --------------------------------------
    //--------------------------------------------------------------------------------------

    /// @notice Fetches the address of the implementation contract currently being used by the proxy
    /// @return the address of the currently used implementation contract
    function getImplementation() external view returns (address) {
        return _getImplementation();
    }

    //--------------------------------------------------------------------------------------
    //-----------------------------------  MODIFIERS  --------------------------------------
    //--------------------------------------------------------------------------------------

    modifier onlyEtherFiNodesManager() {
        require(msg.sender == address(etherFiNodesManager), "Only etherFiNodesManager function");
        _;
    }

    modifier onlyAuctionManager() {
        require(msg.sender == address(auctionManager), "Only auction manager function");
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Caller is not the admin");
        _;
    }
}
