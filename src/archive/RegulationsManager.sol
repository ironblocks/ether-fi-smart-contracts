// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {VennFirewallConsumer} from "@ironblocks/firewall-consumer/contracts/consumers/VennFirewallConsumer.sol";
import "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/security/PausableUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "../interfaces/IRegulationsManager.sol";

contract RegulationsManager is
    VennFirewallConsumer,
    IRegulationsManager,
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    mapping(uint32 => mapping(address => bool)) public isEligible;
    mapping(address => bytes32) public declarationHashes;
    mapping(uint256 => bytes32) public correctVersionHash;

    uint32 public whitelistVersion;

    address public DEPRECATED_admin;
    mapping(address => bool) public admins;

    //--------------------------------------------------------------------------------------
    //-------------------------------------  EVENTS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    event EligibilityConfirmed(uint32 whitelistVersion, bytes32 hash, address user);
    event EligibilityRemoved(uint32 whitelistVersion, address user);
    event whitelistVersionIncreased(uint32 currentDeclaration);

    //--------------------------------------------------------------------------------------
    //----------------------------  STATE-CHANGING FUNCTIONS  ------------------------------
    //--------------------------------------------------------------------------------------

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /// @notice initializes contract
    function initialize() external initializer firewallProtected {
        __Pausable_init();
        __Ownable_init();
        __UUPSUpgradeable_init();
    
		_setAddressBySlot(bytes32(uint256(keccak256("eip1967.firewall")) - 1), address(0));
		_setAddressBySlot(bytes32(uint256(keccak256("eip1967.firewall.admin")) - 1), msg.sender);
	}

    /// @notice sets a user apart of the whitelist, confirming they are not in a blacklisted country
    function confirmEligibility(bytes32 _hash) external whenNotPaused firewallProtected {
        require(correctVersionHash[whitelistVersion] == _hash, "Incorrect hash");
        isEligible[whitelistVersion][msg.sender] = true;
        declarationHashes[msg.sender] = keccak256(abi.encodePacked(_hash, msg.sender));

        emit EligibilityConfirmed(whitelistVersion, _hash, msg.sender);
    }

    /// @notice removes a user from the whitelist
    /// @dev can be called by the owner or the user them self
    /// @param _user the user to remove from the whitelist
    function removeFromWhitelist(address _user) external whenNotPaused firewallProtected {
        require(
            msg.sender == _user || msg.sender == owner(),
            "Incorrect Caller"
        );
        require(
            isEligible[whitelistVersion][_user] == true,
            "User may be in a regulated country"
        );

        isEligible[whitelistVersion][_user] = false;

        emit EligibilityRemoved(whitelistVersion, _user);
    }

    /// @notice resets the whitelist by incrementing the iteration
    /// @dev happens when there is an update to the blacklisted country list
    function initializeNewWhitelist(bytes32 _newVersionHash) external onlyAdmin firewallProtected {
        whitelistVersion++;
        correctVersionHash[whitelistVersion] = _newVersionHash;

        emit whitelistVersionIncreased(whitelistVersion);
    }

    //Pauses the contract
    function pauseContract() external onlyAdmin firewallProtected {
        _pause();
    }

    //Unpauses the contract
    function unPauseContract() external onlyAdmin firewallProtected {
        _unpause();
    }

    /// @notice Updates the address of the admin
    /// @param _newAdmin the new address to set as admin
    function updateAdmin(address _newAdmin, bool _isAdmin) external onlyOwner firewallProtected {
        require(_newAdmin != address(0), "Cannot be address zero");
        admins[_newAdmin] = _isAdmin;
    }

    //--------------------------------------------------------------------------------------
    //-------------------------------  INTERNAL FUNCTIONS   --------------------------------
    //--------------------------------------------------------------------------------------

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
    
    function _msgData() internal view virtual override(Context, ContextUpgradeable) returns (bytes calldata) {
        return super._msgData();
    }

    function _msgSender() internal view virtual override(Context, ContextUpgradeable) returns (address) {
        return super._msgSender();
    }
    //--------------------------------------------------------------------------------------
    //------------------------------------  GETTERS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    function getImplementation() external view returns (address) {
        return _getImplementation();
    }

    //--------------------------------------------------------------------------------------
    //-----------------------------------  MODIFIERS  --------------------------------------
    //--------------------------------------------------------------------------------------

    modifier onlyAdmin() {
        require(admins[msg.sender], "Caller is not the admin");
        _;
    }
}
