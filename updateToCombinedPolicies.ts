// scripts/updateToCombinedPolicies.ts
import { ethers } from "hardhat";
const config = require("./venn.config.json");


async function updateToCombinedPolicies() {
  console.log("Starting policy update...");

  // Get contract factories
  const AllowlistPolicy = await ethers.getContractFactory("AllowlistPolicy");
  const CombinedPoliciesPolicy = await ethers.getContractFactory("CombinedPoliciesPolicy");
  const Firewall = await ethers.getContractFactory("Firewall");

  // Get existing contracts
  const firewall = Firewall.attach("0xbCB78e982e8b8e2b146D91E1Fff0A98AB57930ab"); // You'll need to provide this
  const existingApprovedCallsPolicy = config.networks.holesky.ApprovedCalls;
  
  console.log("Deploying new policies...");
  
  // Deploy new policies
  const allowlistPolicy = await AllowlistPolicy.deploy(firewall.address);
  await allowlistPolicy.deployed();
  console.log("AllowlistPolicy deployed to:", allowlistPolicy.address);

  const combinedPolicy = await CombinedPoliciesPolicy.deploy(firewall.address);
  await combinedPolicy.deployed();
  console.log("CombinedPoliciesPolicy deployed to:", combinedPolicy.address);

  // Get roles
  const POLICY_ADMIN_ROLE = ethers.utils.keccak256(
    ethers.utils.toUtf8Bytes("POLICY_ADMIN_ROLE")
  );

  console.log("Configuring policies...");

  // Approve policies in Firewall
  const approveTx1 = await firewall.setPolicyStatus(allowlistPolicy.address, true);
  await approveTx1.wait();
  const approveTx2 = await firewall.setPolicyStatus(combinedPolicy.address, true);
  await approveTx2.wait();
  console.log("Policies approved in Firewall");

  // Set up roles
  const adminAddress = await firewall.owner(); // Or specify different admin
  const roleTx1 = await allowlistPolicy.grantRole(POLICY_ADMIN_ROLE, adminAddress);
  await roleTx1.wait();
  const roleTx2 = await combinedPolicy.grantRole(POLICY_ADMIN_ROLE, adminAddress);
  await roleTx2.wait();
  console.log("Roles granted to admin:", adminAddress);

  // Configure combined policy
  const combineTx = await combinedPolicy.setAllowedCombinations(
    [existingApprovedCallsPolicy, allowlistPolicy.address],
    [[true, true]] // Both must pass
  );
  await combineTx.wait();
  console.log("Combined policy configured");

  // Get all consumer addresses
  const consumerAddresses = Object.values(config.networks.holesky.contracts);
  console.log(`Updating ${consumerAddresses.length} consumers...`);

  // Remove old policy from all consumers
  const removeTx = await firewall.removeGlobalPolicyForConsumers(
    consumerAddresses,
    existingApprovedCallsPolicy
  );
  await removeTx.wait();
  console.log("Old policy removed from consumers");

  // Add new combined policy to all consumers
  const addTx = await firewall.addGlobalPolicyForConsumers(
    consumerAddresses,
    combinedPolicy.address
  );
  await addTx.wait();
  console.log("New combined policy added to consumers");

  // Configure allowlist
  const allowedAddresses = [
    // Add addresses that should be allowed to interact with the contracts
    adminAddress,
    // Add other addresses as needed
  ];

  console.log("Configuring allowlist with addresses:", allowedAddresses);

  // Add addresses to allowlist for each consumer
  for (const [name, address] of Object.entries(config.networks.holesky.contracts)) {
    const allowlistTx = await allowlistPolicy.setConsumerAllowlist(
      address,
      allowedAddresses,
      true
    );
    await allowlistTx.wait();
    console.log(`Allowlist configured for ${name}`);
  }

  // Verify setup
  console.log("\nVerifying setup...");
  
  for (const [name, address] of Object.entries(config.networks.holesky.contracts)) {
    const policies = await firewall.getActiveGlobalPolicies(address);
    console.log(`${name} policies:`, policies);
    
    for (const allowedAddress of allowedAddresses) {
      const isAllowed = await allowlistPolicy.consumerAllowlist(address, allowedAddress);
      console.log(`${allowedAddress} allowed for ${name}: ${isAllowed}`);
    }
  }

  console.log("\nUpdate complete!");
  
  // Return addresses for reference
  return {
    allowlistPolicy: allowlistPolicy.address,
    combinedPolicy: combinedPolicy.address,
    existingApprovedCallsPolicy
  };
}

// Helper function to handle errors
function handleError(error: any) {
  console.error("Error:", error);
  if (error.data) {
    console.error("Error data:", error.data);
  }
  process.exit(1);
}

// Run the update
if (require.main === module) {
  updateToCombinedPolicies()
    .then((addresses) => {
      console.log("\nDeployed Addresses:", addresses);
      process.exit(0);
    })
    .catch(handleError);
}

export { updateToCombinedPolicies };