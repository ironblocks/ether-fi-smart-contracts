const hre = require("hardhat");
require('dotenv').config();

async function main() {
    const { EETH_CONTRACT_ADDRESS } = process.env;

    console.log("Deploying Drainer contract...");
    console.log("EETH token address:", EETH_CONTRACT_ADDRESS);

    const Drainer = await hre.ethers.getContractFactory("Drainer");
    const drainer = await Drainer.deploy(EETH_CONTRACT_ADDRESS);

    await drainer.deployed();
    console.log("Drainer deployed to:", drainer.address);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });