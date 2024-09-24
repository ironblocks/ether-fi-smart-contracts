// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../../src/helpers/AddressProvider.sol";

contract AddPhaseOneAddressesToProvider is Script {

    /*---- Storage variables ----*/

    AddressProvider public addressProvider;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Load the existing AddressProvider
        addressProvider = AddressProvider(vm.envAddress("CONTRACT_REGISTRY"));

        // Add Phase One contract addresses
        addressProvider.addContract(vm.envAddress("AUCTION_MANAGER_PROXY_ADDRESS"), "AuctionManager");
        addressProvider.addContract(vm.envAddress("STAKING_MANAGER_PROXY_ADDRESS"), "StakingManager");
        addressProvider.addContract(vm.envAddress("ETHERFI_NODES_MANAGER_PROXY_ADDRESS"), "EtherFiNodesManager");
        addressProvider.addContract(vm.envAddress("PROTOCOL_REVENUE_MANAGER_PROXY_ADDRESS"), "ProtocolRevenueManager");
        addressProvider.addContract(vm.envAddress("TNFT_PROXY_ADDRESS"), "TNFT");
        addressProvider.addContract(vm.envAddress("BNFT_PROXY_ADDRESS"), "BNFT");
        addressProvider.addContract(vm.envAddress("TREASURY_ADDRESS"), "Treasury");
        addressProvider.addContract(vm.envAddress("NODE_OPERATOR_MANAGER_ADDRESS"), "NodeOperatorManager");
        // addressProvider.addContract(vm.envAddress("ETHERFI_NODE"), "EtherFiNode");
        // addressProvider.addContract(vm.envAddress("EARLY_ADOPTER_POOL"), "EarlyAdopterPool");

        vm.stopBroadcast();
    }
}