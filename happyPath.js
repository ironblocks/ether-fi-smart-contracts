const { VennClient } = require('@vennbuild/venn-dapp-sdk');
const ethers = require('ethers');
require('dotenv').config();

async function main() {
    const vennURL = process.env.VENN_NODE_URL;
    const vennPolicyAddress = process.env.VENN_POLICY_ADDRESS;
    const nodeOperatorManagerAddress = process.env.NODE_OPERATOR_MANAGER_ADDRESS;
    const auctionManagerAddress = process.env.AUCTION_MANAGER_PROXY_ADDRESS;
    const liquidityPoolAddress = process.env.LIQUIDITY_POOL_PROXY_ADDRESS;
    const deployerPrivateKey = process.env.PRIVATE_KEY;
    const deployerAddress = process.env.DEPLOYER;

    console.log("Initializing connections...");
    const vennClient = new VennClient({ vennURL, vennPolicyAddress });
    const provider = new ethers.providers.JsonRpcProvider(process.env.HOLESKY_RPC_URL);
    const wallet = new ethers.Wallet(deployerPrivateKey, provider);

    // 1. Whitelist the deployer in the NodeOperatorManager
    const nodeOperatorManagerABI = [
        "function addToWhitelist(address _address) external",
        "function isWhitelisted(address _address) external view returns (bool)",
        "function registerNodeOperator(bytes memory _ipfsHash, uint64 _totalKeys) external",
        "function registered(address) external view returns (bool)"
    ];
    const nodeOperatorManagerContract = new ethers.Contract(nodeOperatorManagerAddress, nodeOperatorManagerABI, wallet);

    try {
        console.log("Checking if deployer is whitelisted...");
        const isWhitelisted = await nodeOperatorManagerContract.isWhitelisted(deployerAddress);
        if (!isWhitelisted) {
            console.log("Whitelisting deployer...");
            let data = nodeOperatorManagerContract.interface.encodeFunctionData("addToWhitelist", [deployerAddress]);
            let approvedTransaction = await vennClient.approve({
                from: deployerAddress,
                to: nodeOperatorManagerAddress,
                data,
                value: "0"
            });
            let tx = await wallet.sendTransaction(approvedTransaction);
            await tx.wait();
            console.log("Deployer whitelisted");
        } else {
            console.log("Deployer already whitelisted");
        }

        console.log("Checking if deployer is registered as a node operator...");
        const isRegistered = await nodeOperatorManagerContract.registered(deployerAddress);
        if (!isRegistered) {
            console.log("Registering node operator...");
            const ipfsHash = ethers.utils.toUtf8Bytes("ipfs://test"); // Replace with actual IPFS hash
            const totalKeys = 10; // Replace with desired number of keys
            data = nodeOperatorManagerContract.interface.encodeFunctionData("registerNodeOperator", [ipfsHash, totalKeys]);
            approvedTransaction = await vennClient.approve({
                from: deployerAddress,
                to: nodeOperatorManagerAddress,
                data,
                value: "0"
            });
            tx = await wallet.sendTransaction(approvedTransaction);
            await tx.wait();
            console.log("Node operator registered");
        } else {
            console.log("Deployer already registered as a node operator");
        }

        // 3. Create Bid
        // console.log("Creating bid...");
        // const auctionManagerABI = ["function createBid(uint256 _bidSize, uint256 _bidAmountPerBid) external payable returns (uint256[] memory)"];
        // const auctionManagerContract = new ethers.Contract(auctionManagerAddress, auctionManagerABI, wallet);

        // const bidSize = 1;
        // const bidAmountPerBid = ethers.utils.parseEther("0.1");

        // data = auctionManagerContract.interface.encodeFunctionData("createBid", [bidSize, bidAmountPerBid]);
        // approvedTransaction = await vennClient.approve({
        //     from: deployerAddress,
        //     to: auctionManagerAddress,
        //     data,
        //     value: bidAmountPerBid.mul(bidSize).toString()
        // });
        // tx = await wallet.sendTransaction(approvedTransaction);
        // let receipt = await tx.wait();
        // console.log("Bid created with ID:", receipt.transactionHash);


        // 4. Check and update whitelist status in LiquidityPool
        console.log("Checking if whitelist is enabled...");
        const liquidityPoolABI = [
            "function deposit() external payable",
            "function paused() external view returns (bool)",
            "function unPauseContract() external",
            "function whitelistEnabled() external view returns (bool)",
            "function whitelisted(address) external view returns (bool)",
            "function updateWhitelistedAddresses(address[] calldata _users, bool _value) external"
        ];
        const liquidityPoolContract = new ethers.Contract(liquidityPoolAddress, liquidityPoolABI, wallet);

        const isWhitelistEnabled = await liquidityPoolContract.whitelistEnabled();
        
        if (isWhitelistEnabled) {
            console.log("Checking if deployer is whitelisted in LiquidityPool...");
            const isWhitelisted = await liquidityPoolContract.whitelisted(deployerAddress);
            
            if (!isWhitelisted) {
                console.log("Deployer is not whitelisted. Adding to whitelist...");
                data = liquidityPoolContract.interface.encodeFunctionData("updateWhitelistedAddresses", [[deployerAddress], true]);
                approvedTransaction = await vennClient.approve({
                    from: deployerAddress,
                    to: liquidityPoolAddress,
                    data,
                    value: "0"
                });
                tx = await wallet.sendTransaction(approvedTransaction);
                await tx.wait();
                console.log("Deployer added to LiquidityPool whitelist");
            } else {
                console.log("Deployer is already whitelisted in LiquidityPool");
            }
        } else {
            console.log("Whitelist is not enabled in LiquidityPool");
        }

        // 5. Check if LiquidityPool is paused
        console.log("Checking if LiquidityPool is paused...");
        const isPaused = await liquidityPoolContract.paused();
        if (isPaused) {
            console.log("LiquidityPool is paused. Attempting to unpause...");
            data = liquidityPoolContract.interface.encodeFunctionData("unPauseContract");
            approvedTransaction = await vennClient.approve({
                from: deployerAddress,
                to: liquidityPoolAddress,
                data,
                value: "0"
            });
            tx = await wallet.sendTransaction(approvedTransaction);
            await tx.wait();
            console.log("LiquidityPool unpaused successfully.");
        } else {
            console.log("LiquidityPool is not paused.");
        }

        // Add a deposit attempt expected to fail
        console.log("Attempting deposit that should fail...");
        try {
            const failingTx = await liquidityPoolContract.deposit({
                value: ethers.utils.parseEther("1"),
                gasLimit: 300000  // Force transaction with gas limit
            });
            await failingTx.wait();
        } catch (error) {
            console.log("Expected failure occurred:", error.message);
        }

        // 6. Original Deposit to Liquidity Pool
        console.log("Depositing to Liquidity Pool...");
        data = liquidityPoolContract.interface.encodeFunctionData("deposit");
        approvedTransaction = await vennClient.approve({
            from: deployerAddress,
            to: liquidityPoolAddress,
            data,
            value: ethers.utils.parseEther("1").toString() // Depositing 1 ETH for simplicity
        });
        tx = await wallet.sendTransaction(approvedTransaction);
        await tx.wait();
        console.log("Deposited 1 ETH to Liquidity Pool");

        console.log("Happy path simulation completed without validator launch.");
    } catch (error) {
        console.error("An error occurred:");
        console.error(error.message);
        if (error.error && error.error.message) {
            console.error("Inner error message:", error.error.message);
        }
        if (error.transaction) {
            console.error("Transaction details:", JSON.stringify(error.transaction, null, 2));
        }
    }
}

main().catch(console.error);