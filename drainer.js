const { VennClient } = require('@vennbuild/venn-dapp-sdk');
const { ethers } = require('ethers');
require('dotenv').config();
const hre = require("hardhat");

async function main() {
    // Load environment variables
    const {
        VENN_ACCEPT_RPC_URL,
        VENN_REJECT_RPC_URL,
        EETH_CONTRACT_ADDRESS,
        VENN_POLICY_ADDRESS,
        DRAINER_CONTRACT_ADDRESS,
        PRIVATE_KEY,
        VICTIM_PRIVATE_KEY,
        HOLESKY_RPC_URL
    } = process.env;

    // Initialize Venn Clients for different purposes
    const vennAcceptClient = new VennClient({ 
        vennURL: VENN_ACCEPT_RPC_URL, 
        vennPolicyAddress: VENN_POLICY_ADDRESS 
    });
    const vennRejectClient = new VennClient({ 
        vennURL: VENN_REJECT_RPC_URL, 
        vennPolicyAddress: VENN_POLICY_ADDRESS 
    });

    // Initialize provider and wallets
    const provider = new ethers.providers.JsonRpcProvider(HOLESKY_RPC_URL);
    const attackerWallet = new ethers.Wallet(PRIVATE_KEY, provider);
    const victimWallet = new ethers.Wallet(VICTIM_PRIVATE_KEY, provider);

    // Initialize contract interfaces
    const eethABI = [
        "function approve(address spender, uint256 amount) external returns (bool)",
        "function allowance(address owner, address spender) external view returns (uint256)",
        "function balanceOf(address account) external view returns (uint256)"
    ];
    const eethContract = new ethers.Contract(EETH_CONTRACT_ADDRESS, eethABI, victimWallet);

    const drainerABI = [
        "function executeDrain(address _owner, uint256 _amount) external"
    ];
    const drainerContract = new ethers.Contract(DRAINER_CONTRACT_ADDRESS, drainerABI, attackerWallet);

    /**
     * Function to execute transactions via VennClient
     * @param {VennClient} vennClient - Instance of VennClient
     * @param {ethers.Wallet} wallet - Wallet instance connected to the provider
     * @param {string} to - Recipient address
     * @param {string} data - Encoded function data
     * @param {string} value - ETH value to send
     */
    async function executeTransaction(vennClient, wallet, to, data, value = "0") {
        const approvedTx = await vennClient.approve({
            from: wallet.address,
            to: to,
            data: data,
            value: value
        });
        const txResponse = await wallet.sendTransaction(approvedTx);
        console.log(`Transaction sent. Hash: ${txResponse.hash}`);
        await txResponse.wait();
        console.log("Transaction mined.");
    }

    console.log("\n=== Starting Drainer Attack Simulation ===");

    // Check initial balances
    const victimBalanceBefore = await eethContract.balanceOf(victimWallet.address);
    const drainerBalanceBefore = await eethContract.balanceOf(DRAINER_CONTRACT_ADDRESS);
    console.log(`Victim Balance Before: ${ethers.utils.formatEther(victimBalanceBefore)} EETH`);
    console.log(`Drainer Balance Before: ${ethers.utils.formatEther(drainerBalanceBefore)} EETH`);

    try {
        // Step 1: Victim approves Drainer using Accept RPC
        console.log("\nVictim approving Drainer to spend EETH...");
        const approveAmount = ethers.utils.parseEther("500");
        const approveData = eethContract.interface.encodeFunctionData("approve", [
            DRAINER_CONTRACT_ADDRESS, 
            approveAmount
        ]);
        
        await executeTransaction(vennAcceptClient, victimWallet, EETH_CONTRACT_ADDRESS, approveData);

        // Verify allowance
        const allowance = await eethContract.allowance(victimWallet.address, DRAINER_CONTRACT_ADDRESS);
        console.log(`Allowance After Approval: ${ethers.utils.formatEther(allowance)} EETH`);

        // Step 2: Drainer attempts to drain using Reject RPC (should be blocked)
        console.log("\nAttempting malicious drain (should be blocked)...");
        const drainAmount = ethers.utils.parseEther("500");
        const drainData = drainerContract.interface.encodeFunctionData("executeDrain", [
            victimWallet.address, 
            drainAmount
        ]);

        await executeTransaction(vennRejectClient, attackerWallet, DRAINER_CONTRACT_ADDRESS, drainData);

    } catch (error) {
        if (error.message.includes("Venn Firewall Rejected")) {
            console.log("✅ Drain attempt successfully blocked by Venn Firewall");
        } else {
            console.error("❌ Error:", error.message);
        }
    }

    // Check final balances
    const victimBalanceAfter = await eethContract.balanceOf(victimWallet.address);
    const drainerBalanceAfter = await eethContract.balanceOf(DRAINER_CONTRACT_ADDRESS);
    console.log(`\nVictim Balance After: ${ethers.utils.formatEther(victimBalanceAfter)} EETH`);
    console.log(`Drainer Balance After: ${ethers.utils.formatEther(drainerBalanceAfter)} EETH`);

    console.log("\n=== Simulation Completed ===");
}

main().catch(error => {
    console.error("Error in simulation:", error);
    process.exit(1);
});