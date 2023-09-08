// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { ethers } from "hardhat";

async function main(name: string, symbol: string, key: string) {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  // // We get the contract to deploy
  // const MysteryBox = await ethers.getContractFactory("MysteryBox");
  // const mysteryBox = await MysteryBox.deploy(name, symbol, key);

  // await mysteryBox.deployed();

  // console.log("Greeter deployed to:", mysteryBox.address);

  // deploy fake
  const WitnetMock = await ethers.getContractFactory("WitnetRandomnessFake");
  const _mockRandomizeLatencyBlock = 2;
  const fee = 10 ** 15;

  const witnetMock = await WitnetMock.deploy(_mockRandomizeLatencyBlock, fee);

  await witnetMock.deployed();

  console.log("WitnetRandomnessFake deployed to:", witnetMock.address);
  // WitnetRandomnessFake deployed to: 0x95250dFC15CC25d744c33cC6B458CB3FB6B1Ce3a
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.

// Adjust arguments before deploy onto the mainnets
main(
  "TEST",
  "TTT",
  "0xyarn sompile" + "5FbDB2315678afecb367f032d93F642f64180aa3"
).catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
