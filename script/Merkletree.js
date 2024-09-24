const { MerkleTree } = require("merkletreejs");
 const keccak256 = require("keccak256");
 const fs = require('fs');
 const { ethers } = require("hardhat");

 let walletAddresses = [
     "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
     "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
     "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC",
     "0x90F79bf6EB2c4f870365E785982E1f101E93b906",
     "0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65",
     "0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc",
   ]

 let leafNodes = walletAddresses.map(addr => keccak256(addr));
 let merkletree = new MerkleTree(leafNodes, keccak256, {sortPairs: true});
 let merkleRoot = merkletree.getRoot();

 let buyerOne = leafNodes[0];
 let buyerTwo = leafNodes[1];
 let buyerThree = leafNodes[2];
 let buyerFour = leafNodes[3];
 let buyerFive = leafNodes[4];
 let buyerSix = leafNodes[5];

 let buyerOneMerkleProof = merkletree.getHexProof(buyerOne);
 let buyerTwoMerkleProof = merkletree.getHexProof(buyerTwo);
 let buyerThreeMerkleProof = merkletree.getHexProof(buyerThree);
 let buyerFourMerkleProof = merkletree.getHexProof(buyerFour);
 let buyerFiveMerkleProof = merkletree.getHexProof(buyerFive);
 let buyerSixMerkleProof = merkletree.getHexProof(buyerSix);

 merkleRoot = merkleRoot.toString("hex");
 console.log(merkleRoot);
 console.log(buyerOneMerkleProof);
 console.log(buyerTwoMerkleProof);
 console.log(buyerThreeMerkleProof);
 console.log(buyerFourMerkleProof);
 console.log(buyerFiveMerkleProof);
 console.log(buyerSixMerkleProof);

 module.exports = {
     walletAddresses,
     leafNodes,
     merkletree,
     merkleRoot,
     buyerOneMerkleProof,
     buyerTwoMerkleProof,
     buyerThreeMerkleProof,
     buyerFourMerkleProof,
     buyerFiveMerkleProof,
     buyerSixMerkleProof,
 }