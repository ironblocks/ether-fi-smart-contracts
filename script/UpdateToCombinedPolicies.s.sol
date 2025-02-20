// script/UpdateToCombinedPolicies.s.sol
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {Firewall} from "@ironblocks/onchain-firewall/packages/onchain-firewall/contracts/Firewall.sol";
import {AllowlistPolicy} from "@ironblocks/onchain-firewall/packages/onchain-firewall/contracts/policies/AllowlistPolicy.sol";
import {CombinedPoliciesPolicy} from "@ironblocks/onchain-firewall/packages/onchain-firewall/contracts/policies/CombinedPoliciesPolicy.sol";

contract UpdateToCombinedPoliciesScript is Script {
    // Config values
    address constant FIREWALL_ADDRESS = 0xbCB78e982e8b8e2b146D91E1Fff0A98AB57930ab;
    address constant EXISTING_APPROVED_CALLS = 0xdef93ae7615d0eaC290D95412E3e33B1a13CCc01;

    // Consumer contracts from venn.config.json
    address[] public consumers = [
        0x4C856027Ff11DCD3051D7A4909f07702Fd1BE2d1, // Treasury
        0xBB6aCc1684494afB73476741720FA4101b040288, // StakingManager
        0xd4C9DF24117dD76c83Be4cDE6a3b14E9F4C1F8D0  // AuctionManager
        // ... add all other consumer addresses
    ];

    function setUp() public {}

    function run() public {
        Firewall firewall = Firewall(FIREWALL_ADDRESS);
        address owner = firewall.owner();
        
        console.logString("Firewall owner:");
        console.logAddress(owner);

        vm.startBroadcast();

        // First deploy policies as our deployer
        AllowlistPolicy allowlistPolicy = new AllowlistPolicy();
        console.logString("AllowlistPolicy deployed to:");
        console.logAddress(address(allowlistPolicy));

        CombinedPoliciesPolicy combinedPolicy = new CombinedPoliciesPolicy(FIREWALL_ADDRESS);
        console.logString("CombinedPoliciesPolicy deployed to:");
        console.logAddress(address(combinedPolicy));
        vm.stopBroadcast();

        // Then impersonate Firewall owner to approve the policies
        vm.startPrank(owner);
        firewall.setPolicyStatus(address(allowlistPolicy), true);
        firewall.setPolicyStatus(address(combinedPolicy), true);
        console.logString("Policies approved in Firewall");
        console.logString("Verifying policy approval status:");
        console.logBool(firewall.approvedPolicies(address(allowlistPolicy)));
        console.logBool(firewall.approvedPolicies(address(combinedPolicy)));
        vm.stopPrank();

        // Then continue as deployer for the rest
        vm.startBroadcast();

        // Get roles
        bytes32 POLICY_ADMIN_ROLE = keccak256("POLICY_ADMIN_ROLE");

        // Set up roles
        allowlistPolicy.grantRole(POLICY_ADMIN_ROLE, msg.sender);
        combinedPolicy.grantRole(POLICY_ADMIN_ROLE, msg.sender);
        console.logString("Roles granted to admin:");
        console.logAddress(msg.sender);

        // Configure combined policy
        address[] memory policies = new address[](2);
        policies[0] = EXISTING_APPROVED_CALLS;
        policies[1] = address(allowlistPolicy);

        bool[][] memory combinations = new bool[][](1);
        combinations[0] = new bool[](2);
        combinations[0][0] = true; // ApprovedCalls must pass
        combinations[0][1] = true; // Allowlist must pass

        combinedPolicy.setAllowedCombinations(policies, combinations);
        console.logString("Combined policy configured");

        // Remove old policy from all consumers
        // firewall.removeGlobalPolicyForConsumers(consumers, EXISTING_APPROVED_CALLS);
        // console.logString("Old policy removed from consumers");

        // Add new combined policy to all consumers
        firewall.addGlobalPolicyForConsumers(consumers, address(combinedPolicy));
        console.logString("New combined policy added to consumers");

        // Configure allowlist
        address[] memory allowedAddresses = new address[](1);
        allowedAddresses[0] = owner;
        // Add other addresses as needed

        for (uint i = 0; i < consumers.length; i++) {
            allowlistPolicy.setConsumerAllowlist(consumers[i], allowedAddresses, true);
            console.logString("Allowlist configured for consumer:");
            console.logAddress(consumers[i]);
        }

        // Verify setup
        for (uint i = 0; i < consumers.length; i++) {
            address[] memory activePolicies = firewall.getActiveGlobalPolicies(consumers[i]);
            console.logString("Active policies for consumer:");
            console.logAddress(consumers[i]);
            
            for (uint j = 0; j < allowedAddresses.length; j++) {
                bool isAllowed = allowlistPolicy.consumerAllowlist(consumers[i], allowedAddresses[j]);
                console.logString("Address allowed for consumer:");
                console.logAddress(allowedAddresses[j]);
                console.logBool(isAllowed);
            }
        }

        vm.stopBroadcast();
    }
}