// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../../src/Treasury.sol";
import "../../src/NodeOperatorManager.sol";
import "../../src/EtherFiNodesManager.sol";
import "../../src/EtherFiNode.sol";
import "../../src/BNFT.sol";
import "../../src/TNFT.sol";
import "../../src/archive/ProtocolRevenueManager.sol";
import "../../src/StakingManager.sol";
import "../../src/AuctionManager.sol";
import "../../src/UUPSProxy.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "forge-std/console.sol";

contract DeployPhaseOne is Script {
    using Strings for string;

    /*---- Storage variables ----*/

    UUPSProxy public auctionManagerProxy;
    UUPSProxy public stakingManagerProxy;
    UUPSProxy public etherFiNodeManagerProxy;
    UUPSProxy public protocolRevenueManagerProxy;
    UUPSProxy public TNFTProxy;
    UUPSProxy public BNFTProxy;

    BNFT public BNFTImplementation;
    BNFT public BNFTInstance;

    TNFT public TNFTImplementation;
    TNFT public TNFTInstance;

    AuctionManager public auctionManagerImplementation;
    AuctionManager public auctionManager;

    StakingManager public stakingManagerImplementation;
    StakingManager public stakingManager;

    ProtocolRevenueManager public protocolRevenueManagerImplementation;
    ProtocolRevenueManager public protocolRevenueManager;

    EtherFiNodesManager public etherFiNodesManagerImplementation;
    EtherFiNodesManager public etherFiNodesManager;

    struct suiteAddresses {
        address treasury;
        address nodeOperatorManager;
        address auctionManager;
        address stakingManager;
        address TNFT;
        address BNFT;
        address etherFiNodesManager;
        address protocolRevenueManager;
        address etherFiNode;
    }

    suiteAddresses suiteAddressesStruct;



    function run() external {
        address ethDepositContractAddress;
        if (block.chainid == 31337) {
            // goerli
            ethDepositContractAddress = 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512;
        } else if (block.chainid == 1) {
            ethDepositContractAddress = 0x00000000219ab540356cBB839Cbe05303d7705Fa;
        } else if (block.chainid == 17000) {
            ethDepositContractAddress = 0x4242424242424242424242424242424242424242;
        } else {
            assert(false);
        }

        // Deploy contracts
        Treasury treasury = new Treasury();
        console.log("Treasury deployed at", address(treasury));
        NodeOperatorManager nodeOperatorManagerImplementation = new NodeOperatorManager();
        UUPSProxy nodeOperatorManagerProxy = new UUPSProxy(
            address(nodeOperatorManagerImplementation),
            ""
        );
        NodeOperatorManager nodeOperatorManager = NodeOperatorManager(
            address(nodeOperatorManagerProxy)
        );
        console.log("NodeOperatorManager deployed at", address(nodeOperatorManager));
        nodeOperatorManager.initialize();

        auctionManagerImplementation = new AuctionManager();
        auctionManagerProxy = new UUPSProxy(
            address(auctionManagerImplementation),
            ""
        );
        auctionManager = AuctionManager(address(auctionManagerProxy));
        console.log("AuctionManager deployed at", address(auctionManager));
        auctionManager.initialize(address(nodeOperatorManager));

        stakingManagerImplementation = new StakingManager();
        stakingManagerProxy = new UUPSProxy(
            address(stakingManagerImplementation),
            ""
        );
        stakingManager = StakingManager(address(stakingManagerProxy));
        console.log("StakingManager deployed at", address(stakingManager));
        stakingManager.initialize(
            address(auctionManager),
            ethDepositContractAddress
        );

        BNFTImplementation = new BNFT();
        BNFTProxy = new UUPSProxy(address(BNFTImplementation), "");
        BNFTInstance = BNFT(address(BNFTProxy));
        BNFTInstance.initialize(address(stakingManager));
        console.log("BNFT deployed at", address(BNFTInstance));
        TNFTImplementation = new TNFT();
        TNFTProxy = new UUPSProxy(address(TNFTImplementation), "");
        TNFTInstance = TNFT(address(TNFTProxy));
        TNFTInstance.initialize(address(stakingManager));
        console.log("TNFT deployed at", address(TNFTInstance));

        protocolRevenueManagerImplementation = new ProtocolRevenueManager();
        protocolRevenueManagerProxy = new UUPSProxy(
            address(protocolRevenueManagerImplementation),
            ""
        );
        protocolRevenueManager = ProtocolRevenueManager(
            payable(address(protocolRevenueManagerProxy))
        );
        protocolRevenueManager.initialize();
        console.log("ProtocolRevenueManager deployed at", address(protocolRevenueManager));
        etherFiNodesManagerImplementation = new EtherFiNodesManager();
        etherFiNodeManagerProxy = new UUPSProxy(
            address(etherFiNodesManagerImplementation),
            ""
        );
        etherFiNodesManager = EtherFiNodesManager(
            payable(address(etherFiNodeManagerProxy))
        );
        etherFiNodesManager.initialize(
            address(treasury),
            address(auctionManager),
            address(stakingManager),
            address(TNFTInstance),
            address(BNFTInstance),
            address(0), // TODO
            address(0),
            address(0)
        );
        console.log("EtherFiNodesManager deployed at", address(etherFiNodesManager));
        EtherFiNode etherFiNode = new EtherFiNode();

        // Setup dependencies
        nodeOperatorManager.setAuctionContractAddress(address(auctionManager));

        auctionManager.setStakingManagerContractAddress(
            address(stakingManager)
        );

        protocolRevenueManager.setAuctionManagerAddress(
            address(auctionManager)
        );
        protocolRevenueManager.setEtherFiNodesManagerAddress(
            address(etherFiNodesManager)
        );

        stakingManager.setEtherFiNodesManagerAddress(
            address(etherFiNodesManager)
        );
        stakingManager.registerEtherFiNodeImplementationContract(
            address(etherFiNode)
        );
        stakingManager.registerTNFTContract(address(TNFTInstance));
        stakingManager.registerBNFTContract(address(BNFTInstance));

        vm.stopBroadcast();

        suiteAddressesStruct = suiteAddresses({
            treasury: address(treasury),
            nodeOperatorManager: address(nodeOperatorManager),
            auctionManager: address(auctionManager),
            stakingManager: address(stakingManager),
            TNFT: address(TNFTInstance),
            BNFT: address(BNFTInstance),
            etherFiNodesManager: address(etherFiNodesManager),
            protocolRevenueManager: address(protocolRevenueManager),
            etherFiNode: address(etherFiNode)
        });
            
        

        writeSuiteVersionFile();
        writeNFTVersionFile();
    }

    function setUp() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.envAddress("DEPLOYER");
        vm.startBroadcast(deployerPrivateKey);
        uint64 nonce = 3;
        vm.setNonce(deployer, nonce);
    }

    function _stringToUint(
        string memory numString
    ) internal pure returns (uint256) {
        uint256 val = 0;
        bytes memory stringBytes = bytes(numString);
        for (uint256 i = 0; i < stringBytes.length; i++) {
            uint256 exp = stringBytes.length - i;
            bytes1 ival = stringBytes[i];
            uint8 uval = uint8(ival);
            uint256 jval = uval - uint256(0x30);

            val += (uint256(jval) * (10 ** (exp - 1)));
        }
        return val;
    }

    function writeSuiteVersionFile() internal {
        // Read Current version
        string memory versionString = vm.readLine(
            "release/logs/PhaseOne/version.txt"
        );

        // Cast string to uint256
        uint256 version = _stringToUint(versionString);

        version++;

        // Overwrites the version.txt file with incremented version
        vm.writeFile(
            "release/logs/PhaseOne/version.txt",
            string(abi.encodePacked(Strings.toString(version)))
        );

        // Writes the data to .release file
        vm.writeFile(
            string(
                abi.encodePacked(
                    "release/logs/PhaseOne/",
                    Strings.toString(version),
                    ".release"
                )
            ),
            string(
                abi.encodePacked(
                    Strings.toString(version),
                    "\nTreasury: ",
                    Strings.toHexString(suiteAddressesStruct.treasury),
                    "\nNode Operator Key Manager: ",
                    Strings.toHexString(
                        suiteAddressesStruct.nodeOperatorManager
                    ),
                    "\nAuctionManager: ",
                    Strings.toHexString(suiteAddressesStruct.auctionManager),
                    "\nStakingManager: ",
                    Strings.toHexString(suiteAddressesStruct.stakingManager),
                    "\nEtherFi Node Manager: ",
                    Strings.toHexString(
                        suiteAddressesStruct.etherFiNodesManager
                    ),
                    "\nProtocol Revenue Manager: ",
                    Strings.toHexString(
                        suiteAddressesStruct.protocolRevenueManager
                    )
                )
            )
        );
    }

    function writeNFTVersionFile() internal {
        // Read Current version
        string memory versionString = vm.readLine(
            "release/logs/PhaseOneNFTs/version.txt"
        );

        // Cast string to uint256
        uint256 version = _stringToUint(versionString);

        version++;

        // Overwrites the version.txt file with incremented version
        vm.writeFile(
            "release/logs/PhaseOneNFTs/version.txt",
            string(abi.encodePacked(Strings.toString(version)))
        );

        // Writes the data to .release file
        vm.writeFile(
            string(
                abi.encodePacked(
                    "release/logs/PhaseOneNFTs/",
                    Strings.toString(version),
                    ".release"
                )
            ),
            string(
                abi.encodePacked(
                    Strings.toString(version),
                    "\nTNFT: ",
                    Strings.toHexString(suiteAddressesStruct.TNFT),
                    "\nBNFT: ",
                    Strings.toHexString(suiteAddressesStruct.BNFT)
                )
            )
        );
    }
}
