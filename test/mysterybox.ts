import { expect } from "chai";
import { parseUnits } from "ethers/lib/utils";
import { ethers, network } from "hardhat";
import moment from "moment";
import { ERC721Token, MysteryBox } from "../typechain";
import { overrides, witnetAddress } from "./constants";

let keyContract: ERC721Token;
let mboxContract: MysteryBox;

let keyAddress: string;
let mboxAddress: string;
let signer: string;
let recipient: string;
const price = parseUnits("1.0", "ether");
let totalItems: number = 0;
const launch = moment().unix() + 30;
const lockup = launch + 3600;

function delay(interval: number) {
  return it("should delay", (done) => {
    setTimeout(() => done(), interval);
  }).timeout(interval + 100); // The extra 100ms should guarantee the test will not fail due to exceeded timeout
}

describe("Start Test", function () {
  it("Get signer address", async function () {
    const [owner, addr1] = await ethers.getSigners();
    signer = owner.address;

    if (network.config.chainId === 1001) {
      recipient = "0xdc926E34E73292cD7c48c6fD7375af7D93435D36";
    } else {
      recipient = addr1.address;
    }
    console.log("   - Signer    : ", signer);
    console.log("   - Recipient : ", recipient);
  });
});

describe("Key Contract", function () {
  it("Deploy an ERC-721 Key contract", async function () {
    const ERC721Token = await ethers.getContractFactory("ERC721Token");
    keyContract = await ERC721Token.deploy("Mystery Box Key", "KEY");
    await keyContract.deployed();

    expect(await keyContract.symbol()).to.equal("KEY");

    keyAddress = keyContract.address;
    // console.log("Deployed Key contract : ", keyAddress);
  });
});

describe("MysteryBox Contract", function () {
  it("Deploy a MysteryBox contract", async function () {
    const MysteryBox = await ethers.getContractFactory("MysteryBox");

    mboxContract = await MysteryBox.deploy(
      "Mystery Box",
      "MBX",
      keyAddress,
      "0x0000000000000000000000000000000000000000",
      signer,
      signer,
      [launch, lockup, price, 50], // LAunch, Lockup
      witnetAddress
    );

    await mboxContract.deployed();

    expect(await mboxContract.symbol()).to.equal("MBX");

    mboxAddress = mboxContract.address;
    // console.log("Deployed MysteryBox contract : ", mboxContract.address);
  });

  it("Set mystery box to Key contract", async function () {
    let tx = await keyContract.setMysteryBox(mboxAddress);
    // wait until the transaction is mined
    await tx.wait();
  });

  it("Make MysteryBox items", async function () {
    const uris = [
      "https://ipfs.io/ipfs/QmeJL6hGSHvcxiFJyuwFSG1Yv2MWLsnDKyeQheQdzwnEo3",
      "https://ipfs.io/ipfs/QmXbw7RZwyLDa1q4X9N2RwyEEvjDVCc2L6pJ1oiS4Ehf9S",
      "https://ipfs.io/ipfs/QmV5FRQZLogf8JxGCn4tymPAsQoH74P52WXyYHFgQGi873",
    ];
    const amounts = [10, 10, 10];

    for (let i = 0; i < amounts.length; i++) {
      totalItems = totalItems + amounts[i];
    }

    // Pre-Mint Case
    // const makeItemsTx = await mboxContract.makeItemsLight(
    //   signer,
    //   uris,
    //   amounts
    // );
    // // wait until the transaction is mined
    // await makeItemsTx.wait();
    //
    // const totalSupply = await mboxContract.totalSupply();
    // expect(totalSupply).to.equal(30);
    //
    // const item = await mboxContract.items(totalSupply.toNumber() - 1);
    // expect(item).to.equal(totalSupply.toNumber() - 1);

    // Post-Mint Case
    const makeItemsTx = await mboxContract.registerItems(uris, amounts);
    // wait until the transaction is mined
    await makeItemsTx.wait();

    const items = await mboxContract.totalItems();
    expect(items).to.equal(totalItems);
  });

  it("Set Hard Cap", async function () {
    const tx = await keyContract.setHardCap(
      totalItems,
      "https://ipfs.io/ipfs/QmeJL6hGSHvcxiFJyuwFSG1Yv2MWLsnDKyeQheQdzwnEo3"
    );
    await tx.wait();

    const hardCap = await keyContract.hardCap();

    expect(hardCap.toNumber()).to.be.equal(totalItems);
  });

  // it("Mint 3 Key NFTs", async function () {
  //   // const safeBatchMintTx = await keyContract.safeBatchMint(signer, [
  //   //   "https://ipfs.io/ipfs/QmSNUNTmgoUTomg7kY55Pb7YQoY8tWw3AGC2gozCLtApW1",
  //   //   "https://ipfs.io/ipfs/QmSNUNTmgoUTomg7kY55Pb7YQoY8tWw3AGC2gozCLtApW1",
  //   //   "https://ipfs.io/ipfs/QmSNUNTmgoUTomg7kY55Pb7YQoY8tWw3AGC2gozCLtApW1",
  //   // ]);
  //   const safeBatchMintTx = await keyContract.safeBatchMintLight(
  //     mboxContract.address,
  //     "https://ipfs.io/ipfs/QmSNUNTmgoUTomg7kY55Pb7YQoY8tWw3AGC2gozCLtApW1",
  //     3
  //   );
  //   // wait until the transaction is mined
  //   await safeBatchMintTx.wait();
  //
  //   expect(await keyContract.totalSupply()).to.equal(3);
  // });

  it("Approval", async function () {
    const approveTx = await keyContract.setApprovalForAll(mboxAddress, true);
    // wait until the transaction is mined
    await approveTx.wait();

    const approve = await keyContract.isApprovedForAll(signer, mboxAddress);
    expect(approve, "true");

    // approveTx = await mboxContract.setApprovalForAll(mboxAddress, true);
    // // wait until the transaction is mined
    // await approveTx.wait();
    //
    // approve = await mboxContract.isApprovedForAll(signer, mboxAddress);
    // expect(approve, "true");
  });

  it("Display Information", async function () {
    const launch = await mboxContract.launch();
    console.log("Launch: ", launch);

    const lockup = await mboxContract.lockup();
    console.log("Lockup: ", lockup);

    // approveTx = await mboxContract.setApprovalForAll(mboxAddress, true);
    // // wait until the transaction is mined
    // await approveTx.wait();
    //
    // approve = await mboxContract.isApprovedForAll(signer, mboxAddress);
    // expect(approve, "true");
  });

  // Wait for LAunch time reached
  delay(30000);

  it("Buy Keys", async function () {
    const blockNum = await ethers.provider.getBlockNumber();
    const block = await ethers.provider.getBlock(blockNum);
    const timestamp = block.timestamp;
    console.log("\tblock timestamp = ", timestamp);

    const amount = 1;
    const buyKeyTx = await mboxContract.buyKeyEth(1, {
      value: price.mul(amount),
    });
    // wait until the transaction is mined
    await buyKeyTx.wait();

    expect(await keyContract.balanceOf(signer)).to.equal(1);
  });

  it("Prepare randomness", async function () {
    const value = parseUnits("26250000000000000", "wei").toString();
    const witnetTx = await mboxContract.requestRandomNumber({
      value: value,
    });

    // wait until the transaction is mined
    await witnetTx.wait();

    await expect(mboxContract.latestRandomizingBlock()).not.to.be.equal(0);
  });

  // delay(600000); //  5 ~ 10 Minutes are needed.

  it("Claim items before release time", async function () {
    // await mboxContract.claim(recipient, [0]);
    await expect(mboxContract.claim(recipient, 1)).to.be.revertedWith(
      "Not yet reveal time reached"
    );

    const balance = await mboxContract.balanceOf(recipient);
    expect(balance).to.equal(0);
  });

  it("Wait for release time reached... about 10 seconds", async function () {
    // Just for test purpose
    const blockNum = await ethers.provider.getBlockNumber();
    const block = await ethers.provider.getBlock(blockNum);
    const claimTx = await mboxContract.setLockup(block.timestamp);
    // wait until the transaction is mined
    await claimTx.wait();
  });

  it("Claim items after lockup period", async function () {
    const claimTx = await mboxContract.claim(recipient, 1, overrides);
    // wait until the transaction is mined
    await claimTx.wait();

    const left = await keyContract.balanceOf(signer);
    expect(left).to.equal(0);

    const balance = await mboxContract.balanceOf(recipient);
    expect(balance).to.equal(1);
  });
});
