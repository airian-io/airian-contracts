import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumber } from "ethers";
import fs from "fs";
import { ethers, network, waffle } from "hardhat";
import moment from "moment/moment";
import {
  ERC721Token,
  EvenAllocationTest,
  MysteryBox,
  Subscription,
  WhiteListNFT,
} from "../typechain";

const chainId = network.config.chainId;

const overrides = {
  gasLimit: 400000000,
  gasPrice: 9000000000,
};

let keyContract: ERC721Token;
let keyAddress: string;
let mboxContract: MysteryBox;
let mboxAddress: string;
let subscriptionContract: Subscription;
let evenAllocContract: EvenAllocationTest;

const nWhitelist = 2;
const andor = false;

const whitelistContracts1: WhiteListNFT[] = [];
const whitelistAddrs1: string[] = [];
const whitelistTypes1: boolean[] = [];

const whitelistContracts2: WhiteListNFT[] = [];
const whitelistAddrs2: string[] = [];
const whitelistTypes2: boolean[] = [];

// 테스트 파라미터 >>>
const mboxPrice = ethers.utils.parseUnits("1.0", "ether");
const ticketPriceEth = "1.0"; // 티켓 가격
const ratePriceEth = "1.0"; // 비례 배분 가격
const evenPriceEth = "2.0"; // 균등 배분 가격

const nUsers = 5; // 청약 참여자 수
let totNFTs = 0; // 총 판매 NFT 수

const maxTicket = 5;
const perTicket = 1;
const launch = moment().unix();
// <<<

const allocNFTs1: number[] = [];
const allocNFTs2: number[] = [];
const refunds1: BigNumber[] = [];
const refunds2: BigNumber[] = [];
const balancesBefore1: BigNumber[] = [];
const balancesBefore2: BigNumber[] = [];
const balancesAfter1: BigNumber[] = [];
const balancesAfter2: BigNumber[] = [];
const payments1: BigNumber[] = [];
const payments2: BigNumber[] = [];

let signers: SignerWithAddress[] = [];

function delay(interval: number) {
  return it("should delay", (done) => {
    setTimeout(() => done(), interval);
  }).timeout(interval + 100); // The extra 100ms should guarantee the test will not fail due to exceeded timeout
}

function calculationBy2(x: number, y: number): number {
  return x * parseFloat(ratePriceEth) + y * parseFloat(evenPriceEth);
}

function calculationBy1(x: number): number {
  return x * parseFloat(ticketPriceEth);
}

describe("Unified Test on Hardhat", function () {
  it("Get signer address", async function () {
    signers = await ethers.getSigners();
  });

  it("Deploy an ERC-721 Key contract", async function () {
    const ERC721Token = await ethers.getContractFactory("ERC721Token");
    keyContract = await ERC721Token.deploy("Mystery Box Key", "KEY");
    await keyContract.deployed();

    expect(await keyContract.symbol()).to.equal("KEY");

    keyAddress = keyContract.address;
    // console.log("\tDeployed Key contract : ", keyAddress);
  });

  it("Deploy MysteryBox Contract", async function () {
    const mysteryBox = await ethers.getContractFactory("MysteryBox");

    mboxContract = await mysteryBox.deploy(
      "Mystery Box",
      "MBX",
      keyAddress, // use Subscription
      "0x0000000000000000000000000000000000000000", // Klay
      signers[0].address,
      signers[1].address,
      [launch, 0, mboxPrice, 50], // Set by Subscription Contract
      "0xB4B2E2e00e9d6E5490d55623E4F403EC84c6D33f" // Baobab WitNet Randomness Contract
    );

    await mboxContract.deployed();

    expect(await mboxContract.symbol()).to.equal("MBX");

    mboxAddress = mboxContract.address;
    console.log("\tDeployed MysteryBox Contract : ", mboxAddress);
  });

  it("Set mystery box to Key contract", async function () {
    let tx = await keyContract.setMysteryBox(mboxAddress);
    // wait until the transaction is mined
    await tx.wait();
  });

  it("Register MysteryBox Items", async function () {
    const uris = [
      "https://ipfs.io/ipfs/QmeJL6hGSHvcxiFJyuwFSG1Yv2MWLsnDKyeQheQdzwnEo3",
      "https://ipfs.io/ipfs/QmXbw7RZwyLDa1q4X9N2RwyEEvjDVCc2L6pJ1oiS4Ehf9S",
      "https://ipfs.io/ipfs/QmV5FRQZLogf8JxGCn4tymPAsQoH74P52WXyYHFgQGi873",
    ];
    const amounts = [10, 10, 10]; // totalSupply = 30
    // Post-Mint Case
    const makeItemsTx = await mboxContract.registerItems(uris, amounts);
    // wait until the transaction is mined
    await makeItemsTx.wait();

    for (let i = 0; i < amounts.length; i++) {
      totNFTs = totNFTs + amounts[i];
    }

    const items = await mboxContract.totalItems();
    expect(items).to.equal(totNFTs);
  });

  // it("Mint Key NFTs", async function () {
  //   const safeBatchMintTx = await keyContract.safeBatchMintLight(
  //     mboxAddress,
  //     "https://ipfs.io/ipfs/QmSNUNTmgoUTomg7kY55Pb7YQoY8tWw3AGC2gozCLtApW1",
  //     totNFTs
  //   );
  //   // wait until the transaction is mined
  //   await safeBatchMintTx.wait();
  //
  //   expect(await keyContract.totalSupply()).to.equal(totNFTs);
  //   expect(await keyContract.balanceOf(mboxAddress)).to.equal(totNFTs);
  // });

  it("Set Hard Cap - Unified Test", async function () {
    const tx = await keyContract.setHardCap(
      totNFTs,
      "https://ipfs.io/ipfs/QmeJL6hGSHvcxiFJyuwFSG1Yv2MWLsnDKyeQheQdzwnEo3"
    );
    await tx.wait();

    const hardCap = await keyContract.hardCap();

    expect(hardCap.toNumber()).to.be.equal(totNFTs);
  });

  it("Deploy WhitelistNFT for Subscription", async function () {
    const whiteList = await ethers.getContractFactory("WhiteListNFT");
    for (let i = 0; i < nWhitelist; i++) {
      whitelistContracts1[i] = await whiteList.deploy(
        "WhiteList Test",
        "TST",
        true,
        i % 2 === 0
      );
      await whitelistContracts1[i].deployed();

      expect(whitelistContracts1[i].address !== "");
      console.log(
        "\tDeployed WhitelistNFT Contract : ",
        whitelistContracts1[i].address
      );

      whitelistAddrs1.push(whitelistContracts1[i].address);
      whitelistTypes1.push(i % 2 === 0);
    }
  });

  it("Add white List", async function () {
    const list = [];

    if (chainId === 1001) {
      // eslint-disable-next-line node/no-unsupported-features/node-builtins
      const jsonData = await fs.promises.readFile(
        "./test/data/list.data",
        "utf8"
      );
      const allList = JSON.parse(jsonData);
      for (let i = 0; i < nUsers; i++) {
        list.push(allList[i]);
      }
    } else {
      for (let i = 0; i < nUsers; i++) {
        list.push(signers[i].address);
      }
      await fs.writeFileSync("./test/data/list.data", JSON.stringify(list));
    }
    // console.log('\t', list);

    for (let i = 0; i < nWhitelist; i++) {
      const tx = await whitelistContracts1[i].addWhitelist(list, 0);
      const receipt = await tx.wait();
      console.log("\taddWhitelist Hash : ", receipt.transactionHash);

      // @ts-ignore
      expect(receipt?.events[0].args[1]).to.be.equal(nUsers);
      // @ts-ignore
      const target = receipt?.events[0].args[0];
      expect(target).to.be.equal(0);
    }
  });

  it("BatchMint to whitelistNFT", async function () {
    for (let i = 0; i < nWhitelist; i++) {
      const tx = await whitelistContracts1[i].safeBatchMintToWhitelist(
        "https://ipfs.io/ipfs/QmSNUNTmgoUTomg7kY55Pb7YQoY8tWw3AGC2gozCLtApW1",
        0
      );
      const receipt = await tx.wait();
      console.log(
        "\tsafeBatchMintToWhitelist Hash : ",
        receipt.transactionHash
      );

      const totalSupply = await whitelistContracts1[i].totalSupply();
      expect(totalSupply).to.be.equal(nUsers);
    }
  });

  it("Deploy Subscription Contract", async function () {
    const [payment, treasury] = await ethers.getSigners();
    const ratePrice: BigNumber = ethers.utils.parseUnits(ratePriceEth, "ether");
    const evenPrice: BigNumber = ethers.utils.parseUnits(evenPriceEth, "ether");
    const subscription = await ethers.getContractFactory("Subscription");
    /**
     * index 0 = _ratePrice : 비례 배분 가격
     * index 1 = _evenPrice : 균등 배분 가격
     * index 2 = _amount : NFT 총수량
     * index 3 = _rate : 비례 배분 수량 비율
     * index 4 = _shareRate : 청약 Klaybay 수수료율
     * index 5 = _mboxRate : 미스터리박스 Klaybay 수수료율
     * index 6 = _launch : Staking 시작 시간
     * index 7 = _startClaim : Claim 시작 시간
     * _quote : Quote Token 주소
     * _payment : 게임사 지갑
     * _treasury : Klaybay 수수료 지갑
     * _whitelist : Whitelist NFT 목록
     * _types : Whitelist NFT 유형
     * _andor : Whitelist NFT 검증 방식
     * _mysterybox : 미스터리박스 컨트랙 주소
     * witnetRandomness : WitNet 컨트랙 주소
     **/
    const configs: any[] = [];
    // Caution : The order of values is very import.
    configs.push(ratePrice);
    configs.push(evenPrice);
    configs.push(totNFTs / 2);
    configs.push(50); // 50%
    configs.push(25); // 2.5%
    configs.push(50); // 5%
    configs.push(launch + 60);
    configs.push(launch + 120);

    subscriptionContract = await subscription.deploy(
      configs,
      "0x0000000000000000000000000000000000000000",
      payment.address,
      treasury.address,
      mboxAddress,
      whitelistAddrs1,
      whitelistTypes1,
      andor,
      "0xB4B2E2e00e9d6E5490d55623E4F403EC84c6D33f"
    );
    await subscriptionContract.deployed();

    expect(subscriptionContract.address !== "");
    console.log(
      "\tDeployed Subscription Contract : ",
      subscriptionContract.address
    );
  });

  it("Set Subscription Contract to MysteryBox", async function () {
    // Post-Mint Case
    const tx = await mboxContract.setSubscription(
      subscriptionContract.address,
      2,
      totNFTs / 2
    );
    // wait until the transaction is mined
    await tx.wait();

    const subscription = await mboxContract.subInfos(0);
    expect(subscription[0]).to.equal(subscriptionContract.address);
  });

  it("Deploy WhitelistNFT for EvenAllocation", async function () {
    const whiteList = await ethers.getContractFactory("WhiteListNFT");
    for (let i = 0; i < nWhitelist; i++) {
      whitelistContracts2[i] = await whiteList.deploy(
        "WhiteList Test",
        "TST",
        true,
        i % 2 === 0
      );
      await whitelistContracts2[i].deployed();

      expect(whitelistContracts2[i].address !== "");
      console.log(
        "\tDeployed WhitelistNFT Contract : ",
        whitelistContracts2[i].address
      );

      whitelistAddrs2.push(whitelistContracts2[i].address);
      whitelistTypes2.push(i % 2 === 0);
    }
  });

  it("Add white List", async function () {
    signers = await ethers.getSigners();

    const list = [];

    if (chainId === 1001) {
      // eslint-disable-next-line node/no-unsupported-features/node-builtins
      const jsonData = await fs.promises.readFile(
        "./test/data/list.data",
        "utf8"
      );
      const allList = JSON.parse(jsonData);
      for (let i = 0; i < nUsers; i++) {
        list.push(allList[i]);
      }
    } else {
      for (let i = 0; i < nUsers; i++) {
        list.push(signers[i].address);
      }
      await fs.writeFileSync("./test/data/list.data", JSON.stringify(list));
    }
    // console.log('\t', list);

    for (let i = 0; i < nWhitelist; i++) {
      const tx = await whitelistContracts2[i].addWhitelist(list, 0);
      const receipt = await tx.wait();
      console.log("\taddWhitelist Hash : ", receipt.transactionHash);

      // @ts-ignore
      expect(receipt?.events[0].args[1]).to.be.equal(nUsers);
      // @ts-ignore
      const target = receipt?.events[0].args[0];
      expect(target).to.be.equal(0);
    }
  });

  it("BatchMint to whitelistNFT", async function () {
    for (let i = 0; i < nWhitelist; i++) {
      const tx = await whitelistContracts2[i].safeBatchMintToWhitelist(
        "https://ipfs.io/ipfs/QmSNUNTmgoUTomg7kY55Pb7YQoY8tWw3AGC2gozCLtApW1",
        0
      );
      const receipt = await tx.wait();
      console.log(
        "\tsafeBatchMintToWhitelist Hash : ",
        receipt.transactionHash
      );

      const totalSupply = await whitelistContracts2[i].totalSupply();
      expect(totalSupply).to.be.equal(nUsers);
    }
  });

  it("Deploy EvenAllocation Contract", async function () {
    const [payment, treasury] = await ethers.getSigners();
    const price: BigNumber = ethers.utils.parseUnits(ticketPriceEth, "ether");
    const evenAllocation = await ethers.getContractFactory(
      "EvenAllocationTest"
    );
    /**
     * index 0 = _price : 가격
     * index 1 = _amount : NFT 총수량
     * index 2 = _shareRate : 청약 Klaybay 수수료율
     * index 3 = _mboxRate : 미스터리박스 Klaybay 수수료율
     * index 4 = _launchg : Buy 가능 시간
     * index 5 = _startClaim : Claim 가능 시간
     * index 6 = _maxTicket : 지갑 당 최대 티켓
     * index 7 = _perTicket : 티켓 당 NFT 수량
     * _quote : Quote Token 주소
     * _payment : 게임사 지갑
     * _treasury : Klaybay 수수료 지갑
     * _whitelist : Whitelist NFT 목록
     * _types : Whitelist NFT 유형
     * _andor : Whitelist NFT 검증 방식
     * _mysterybox : 미스터리박스 컨트랙 주소
     * witnetRandomness : WitNet 컨트랙 주소
     **/
    const configs: any[] = [];
    // Caution : The order of values is very import.
    configs.push(price);
    configs.push(totNFTs / 2);
    configs.push(25); // 2.5%
    configs.push(50); // 5%
    configs.push(launch + 60);
    configs.push(launch + 120);
    configs.push(maxTicket);
    configs.push(perTicket);

    evenAllocContract = await evenAllocation.deploy(
      configs,
      "0x0000000000000000000000000000000000000000",
      payment.address,
      treasury.address,
      mboxAddress,
      whitelistAddrs2,
      whitelistTypes2,
      andor,
      "0xB4B2E2e00e9d6E5490d55623E4F403EC84c6D33f"
    );
    await evenAllocContract.deployed();

    expect(evenAllocContract.address !== "");
    console.log(
      "\tDeployed EvenAllocation Contract : ",
      evenAllocContract.address
    );
  });

  it("Set EvenAllocation Contract to MysteryBox", async function () {
    // Post-Mint Case
    const tx = await mboxContract.setSubscription(
      evenAllocContract.address,
      1,
      totNFTs / 2
    );
    // wait until the transaction is mined
    await tx.wait();

    const subscription = await mboxContract.subInfos(1);
    expect(subscription[0]).to.equal(evenAllocContract.address);
  });

  // it("Set Launch Date to MysteryBox", async function () {
  //   // Post-Mint Case
  //   const tx = await mboxContract.setLaunch(launch);
  //   // wait until the transaction is mined
  //   await tx.wait();
  //
  //   const paused = await mboxContract.paused();
  //   expect(paused).to.equal(false);
  // });

  it("Set Approval to Whitelist", async function () {
    for (let i = 0; i < nWhitelist; i++) {
      for (let j = 0; j < nUsers; j++) {
        // for Subscription
        let approveTx = await whitelistContracts1[i]
          .connect(signers[j])
          .setApprovalForAll(subscriptionContract.address, true);
        // wait until the transaction is mined
        await approveTx.wait();

        let approve = await whitelistContracts1[i].isApprovedForAll(
          signers[j].address,
          subscriptionContract.address
        );
        expect(approve, "true");

        // for EvenAllocation
        approveTx = await whitelistContracts2[i]
          .connect(signers[j])
          .setApprovalForAll(evenAllocContract.address, true);
        // wait until the transaction is mined
        await approveTx.wait();

        approve = await whitelistContracts2[i].isApprovedForAll(
          signers[j].address,
          evenAllocContract.address
        );
        expect(approve, "true");
      }
    }
  });

  // it("Prepare randomness", async function () {
  //   const value = parseUnits("26250000000000000", "wei").toString();
  //   const witnetTx = await subscriptionContract.requestRandomNumber({
  //     value: value,
  //   });
  //
  //   // wait until the transaction is mined
  //   await witnetTx.wait();
  //
  //   await expect(mboxContract.latestRandomizingBlock()).not.to.be.equal(0);
  // });
  //
  // delay(600000); //  5 ~ 10 Minutes are needed.

  function generateRandom(maxLimit: number) {
    let rand = Math.random() * maxLimit;
    rand = Math.floor(rand); // 99
    return rand;
  }

  // Wait foe Launch time reached
  delay(60000);

  it("Staking", async function () {
    for (let i = 0; i < nUsers; i++) {
      const payment =
        generateRandom(10) * parseFloat(ratePriceEth) +
        generateRandom(10) * parseFloat(evenPriceEth) +
        Math.max(parseFloat(ratePriceEth), parseFloat(evenPriceEth)); // Minimum staking = choose the bigger both two prices

      payments1.push(ethers.utils.parseUnits(payment.toString(), "ether"));

      const applyTx = await subscriptionContract
        .connect(signers[i])
        .stakingEth({
          value: ethers.utils.parseUnits(payment.toString(), "ether"),
        });

      const txReceipt = await applyTx.wait();

      // console.log("\t--->", txReceipt);
      let eventIx = 0;
      if (andor) {
        eventIx = 4;
      } else {
        eventIx = 2;
      }
      // @ts-ignore
      expect(txReceipt?.events[eventIx].args[0] ?? "0x0").to.equal(
        signers[i].address
      );
      // @ts-ignore
      expect(txReceipt?.events[eventIx].args[2] ?? "0").to.equal(payments1[i]);
    }

    for (let i = 0; i < nWhitelist; i++) {
      if (!andor && i > 0) break;
      const balance = await whitelistContracts1[i].balanceOf(
        subscriptionContract.address
      );
      expect(balance).to.equal(nUsers);
    }
  });

  let addAmount: number;
  const tIndex = 1;

  it("Staking More", async function () {
    addAmount =
      generateRandom(10) * parseFloat(ratePriceEth) +
      generateRandom(10) * parseFloat(evenPriceEth) +
      Math.max(parseFloat(ratePriceEth), parseFloat(evenPriceEth)); // Minimum staking = choose the bigger both two prices

    const applyTx = await subscriptionContract
      .connect(signers[tIndex])
      .stakingEth({
        value: ethers.utils.parseUnits(addAmount.toString(), "ether"),
      });

    const txReceipt = await applyTx.wait();
    // @ts-ignore
    expect(txReceipt?.events[0].args[0] ?? "0x0").to.equal(
      signers[tIndex].address
    );
    // @ts-ignore
    expect(txReceipt?.events[0].args[2] ?? "0").to.equal(
      ethers.utils.parseUnits(addAmount.toString(), "ether")
    );
  });

  it("Unstaking", async function () {
    const tx = await subscriptionContract
      .connect(signers[tIndex])
      .unStaking(ethers.utils.parseUnits(addAmount.toString(), "ether"));
    const txReceipt = await tx.wait();

    // @ts-ignore
    expect(txReceipt?.events[0].args[0] ?? "0x0").to.equal(
      signers[tIndex].address
    );
    // @ts-ignore
    expect(txReceipt?.events[0].args[1] ?? "0").to.equal(
      ethers.utils.parseUnits(addAmount.toString(), "ether")
    );
  });

  it("Get least fund to get a key", async function () {
    const totalFund = await subscriptionContract.totalFund();
    console.log("\tTotal Fund  = ", totalFund);

    const rateAmount = await subscriptionContract.rateAmount();
    console.log("\tRate Amount = ", rateAmount);

    const leastFund = await subscriptionContract.getLeastFund();
    console.log("\tLeast Fund  = ", leastFund);
    expect(parseFloat(ethers.utils.formatEther(leastFund))).to.gt(0);
  });

  // it("Allocation Subscription", async function () {
  //   const allocTx = await subscriptionContract.allocation(overrides);
  //   const txReceipt = await allocTx.wait();
  //
  //   // console.log('\t', txReceipt);
  //   const gasUsed: BigNumber = txReceipt.cumulativeGasUsed.mul(
  //     // ethers.utils.parseUnits("250", "gwei")  // Klaytn의 경우
  //     txReceipt.effectiveGasPrice // 9 gwei 로 나옴
  //   );
  //   // console.log('\t', txReceipt.cumulativeGasUsed, txReceipt.effectiveGasPrice);
  //   // console.log('\t', ethers.utils.formatEther(gasUsed));
  //
  //   const status = await subscriptionContract.allocStatus();
  //   expect(status).to.equal(true);
  // });
  //
  // it("Check Allocation Result", async function () {
  //   // const totalFund = await subscriptionContract.totalFund();
  //   // console.log("\t= Total Funds =>", totalFund);
  //
  //   // const evenAmount = await subscriptionContract.evenAmount();
  //   // console.log("\t= even amount =>", evenAmount);
  //
  //   let booking;
  //   let nNFTs = 0;
  //   let totFunds = 0;
  //   for (let i = 0; i < nUsers; i++) {
  //     // Caution : Skip index 0 in the smart contract
  //     booking = await subscriptionContract.booking(i + 1);
  //
  //     const cost: number = calculationBy2(
  //       booking.rateAlloc.toNumber(),
  //       booking.evenAlloc.toNumber()
  //     );
  //
  //     allocNFTs1.push(booking.totalAlloc.toNumber());
  //     refunds1.push(
  //       payments1[i].sub(ethers.utils.parseUnits(cost.toString(), "ether"))
  //     );
  //
  //     console.log(
  //       `\tUser #${i + 1} ${ethers.utils.formatEther(
  //         payments1[i]
  //       )} : ${booking.totalAlloc.toNumber()} = ${booking.rateAlloc.toNumber()} + ${booking.evenAlloc.toNumber()} = ${cost} Klay`
  //     );
  //     // console.log('\t', booking);
  //
  //     expect(cost).to.be.at.most(
  //       parseFloat(ethers.utils.formatEther(payments1[i]))
  //     );
  //
  //     nNFTs = nNFTs + booking.totalAlloc.toNumber();
  //     totFunds = totFunds + parseFloat(ethers.utils.formatEther(payments1[i]));
  //   }
  //
  //   console.log(
  //     `\tTotal NFTs = ${totNFTs}, Total Fund = ${totFunds}, Left NFTs = ${
  //       totNFTs - nNFTs
  //     }`
  //   );
  // });

  it("Buying Tickets", async function () {
    for (let i = 0; i < nUsers; i++) {
      const nTickets = generateRandom(maxTicket - 1) + 1;
      // console.log("\t==> ", nTickets);
      const payment = nTickets * parseFloat(ticketPriceEth);

      payments2.push(ethers.utils.parseUnits(payment.toString(), "ether"));

      const applyTx = await evenAllocContract
        .connect(signers[i])
        .buyTicketEth(nTickets, {
          value: ethers.utils.parseUnits(payment.toString(), "ether"),
        });

      const txReceipt = await applyTx.wait();

      let eventIx = 0;
      if (andor) {
        eventIx = 4;
      } else {
        eventIx = 2;
      }
      // @ts-ignore
      // console.log("\t===>", txReceipt.events[eventIx]);
      // @ts-ignore
      expect(txReceipt?.events[eventIx].args[0] ?? "0x0").to.equal(
        signers[i].address
      );
      // @ts-ignore
      expect(txReceipt?.events[eventIx].args[2] ?? "0").to.equal(payments2[i]);
    }

    for (let i = 0; i < nWhitelist; i++) {
      if (!andor && i > 0) break;
      const balance = await whitelistContracts2[i].balanceOf(
        evenAllocContract.address
      );
      expect(balance).to.equal(nUsers);
    }
  });

  // it("Allocation EvenAllocation", async function () {
  //   const allocTx = await evenAllocContract.allocation(overrides);
  //   const txReceipt = await allocTx.wait();
  //
  //   // console.log('\t', txReceipt);
  //   const gasUsed: BigNumber = txReceipt.cumulativeGasUsed.mul(
  //     // ethers.utils.parseUnits("250", "gwei")  // Klaytn의 경우
  //     txReceipt.effectiveGasPrice // 9 gwei 로 나옴
  //   );
  //   // console.log('\t', txReceipt.cumulativeGasUsed, txReceipt.effectiveGasPrice);
  //   // console.log('\t', ethers.utils.formatEther(gasUsed));
  //
  //   const status = await evenAllocContract.allocStatus();
  //   expect(status).to.equal(true);
  // });
  //
  // it("Check Allocation Result", async function () {
  //   // const totalFund = await evenAllocContract.totalFund();
  //   // console.log("\t= Total Funds =>", totalFund);
  //
  //   // const evenAmount = await evenAllocContract.evenAmount();
  //   // console.log("\t= even amount =>", evenAmount);
  //
  //   let booking;
  //   let nNFTs = 0;
  //
  //   for (let i = 0; i < nUsers; i++) {
  //     // Caution : Skip index 0 in the smart contract
  //     booking = await evenAllocContract.booking(i + 1);
  //
  //     const cost: number = calculationBy1(booking.allocated.toNumber());
  //
  //     allocNFTs2.push(booking.allocated.toNumber());
  //     refunds2.push(
  //       payments2[i].sub(ethers.utils.parseUnits(cost.toString(), "ether"))
  //     );
  //
  //     console.log(
  //       `\tUser #${i + 1} ${ethers.utils.formatEther(
  //         payments2[i]
  //       )} : ${booking.allocated.toNumber()} = ${cost} Klay`
  //     );
  //     // console.log('\t', booking);
  //
  //     expect(cost).to.be.at.most(
  //       parseFloat(ethers.utils.formatEther(payments2[i]))
  //     );
  //
  //     nNFTs = nNFTs + booking.allocated.toNumber();
  //   }
  //
  //   console.log(`\tTotal NFTs = ${totNFTs}, Left NFTs = ${totNFTs - nNFTs}`);
  // });

  it("claim before Claim Time", async function () {
    await expect(
      subscriptionContract.connect(signers[0]).claim()
    ).to.be.revertedWith("Claim time is not yet reached");

    await expect(
      evenAllocContract.connect(signers[0]).claim()
    ).to.be.revertedWith("Claim time is not yet reached");
  });

  // it("Wait for release time reached... about 10 seconds", async function () {
  //   // Just for test purpose
  //   const claimTx = await mboxContract.setReleaseForTest(); // 5 seconds lockup period
  //   // wait until the transaction is mined
  //   await claimTx.wait();
  // });

  delay(60000); //  7 Seconds

  // This Test is possible only on the real chain.
  it("Claim Subscription", async function () {
    const provider = waffle.provider;

    for (let i = 0; i < nUsers; i++) {
      const beforeBalance: BigNumber = await provider.getBalance(
        signers[i].address
      );
      balancesBefore1.push(beforeBalance);

      const before: BigNumber = await provider.getBalance(
        subscriptionContract.address
      );

      const tx = await subscriptionContract.connect(signers[i]).claim();
      const receipt = await tx.wait();
      // @ts-ignore
      // console.log("\t===> ", receipt.events);

      const afterBalance: BigNumber = await provider.getBalance(
        signers[i].address
      );
      balancesAfter1.push(afterBalance);

      const after: BigNumber = await provider.getBalance(
        subscriptionContract.address
      );

      const gap = before.sub(after);
      // console.log('\t', before, " - ", after, " = ", gap);
      // console.log('\t', payments1[i]);

      expect(gap).to.deep.equal(payments1[i]);
    }
  });

  it("Check Subscription Claim Result", async function () {
    // Check refunded whitelist NFTs
    for (let i = 0; i < nWhitelist; i++) {
      if (!andor && i === 1) break;
      for (let j = 0; j < nUsers; j++) {
        const balance = await whitelistContracts1[i].balanceOf(
          signers[j].address
        );
        if (i % 2 === 0) {
          // One Time NFT will be burn
          expect(balance).to.equal(0);
        } else {
          // The others will be returned
          expect(balance).to.equal(1);
        }
      }
    }

    // Check refunded klays
    // for (let i = 0; i < nUsers; i++) {
    //   const zero: BigNumber = ethers.utils.parseUnits("0", "ether");
    //   if (refunds1[i].eq(zero)) {
    //     // gas consumed for claim
    //     expect(balancesBefore1[i].sub(balancesAfter1[i])).to.gt(zero);
    //   } else {
    //     // gas consumed for claim but balance increased by refunded klay
    //     expect(balancesAfter1[i].sub(balancesBefore1[i])).to.gt(zero);
    //   }
    // }

    // Check keys sent to me
    for (let i = 0; i < nUsers; i++) {
      const balance = await keyContract.balanceOf(signers[i].address);
      expect(balance).to.equal(allocNFTs1[i]);
    }
  });

  // This Test is possible only on the real chain.
  it("Claim EvenAllocation", async function () {
    const provider = waffle.provider;

    for (let i = 0; i < nUsers; i++) {
      const beforeBalance: BigNumber = await provider.getBalance(
        signers[i].address
      );
      balancesBefore2.push(beforeBalance);

      const before: BigNumber = await provider.getBalance(
        evenAllocContract.address
      );

      const tx = await evenAllocContract.connect(signers[i]).claim();
      const receipt = await tx.wait();
      // @ts-ignore
      // console.log('\t', receipt.events[0].args);

      const afterBalance: BigNumber = await provider.getBalance(
        signers[i].address
      );
      balancesAfter2.push(afterBalance);

      const after: BigNumber = await provider.getBalance(
        evenAllocContract.address
      );

      const gap = before.sub(after);
      // console.log('\t', before, " - ", after, " = ", gap);
      // console.log('\t', payments2[i]);

      expect(gap).to.deep.equal(payments2[i]);
    }
  });

  it("Check EvenAllocation Claim Result", async function () {
    // Check refunded whitelist NFTs
    for (let i = 0; i < nWhitelist; i++) {
      if (!andor && i === 1) break;
      for (let j = 0; j < nUsers; j++) {
        const balance = await whitelistContracts2[i].balanceOf(
          signers[j].address
        );
        if (i % 2 === 0) {
          // One Time NFT will be burn
          expect(balance).to.equal(0);
        } else {
          // The others will be returned
          expect(balance).to.equal(1);
        }
      }
    }

    // Check refunded klays
    // for (let i = 0; i < nUsers; i++) {
    //   const zero: BigNumber = ethers.utils.parseUnits("0.0", "ether");
    //   if (refunds2[i].gt(zero)) {
    //     // gas consumed for claim but balance increased by refunded klay
    //     expect(balancesAfter2[i].sub(balancesBefore2[i])).to.gt(zero);
    //   }
    //   // else {
    //   //   // gas consumed for claim
    //   //   expect(balancesBefore2[i].sub(balancesAfter2[i])).to.gt(zero);
    //   // }
    // }

    // Check minted items to me
    for (let i = 0; i < nUsers; i++) {
      const balance = await keyContract.balanceOf(signers[i].address);
      expect(balance).to.equal(allocNFTs1[i] + allocNFTs2[i] * perTicket);
    }
  });

  it("Claim items", async function () {
    for (let i = 0; i < nUsers; i++) {
      const balance = await keyContract.balanceOf(signers[i].address);
      // console.log("\t---> ", balance);

      let tx = await keyContract
        .connect(signers[i])
        .setApprovalForAll(mboxAddress, true);
      await tx.wait();

      tx = await mboxContract
        .connect(signers[i])
        .claim(signers[i].address, balance, overrides);
      await tx.wait();
    }
  });

  it("Get token ID range", async function () {
    const info1 = await mboxContract.getSubInfos(subscriptionContract.address); // 5 seconds lockup period

    console.log(
      `\tSubscription token range : ${info1[1].toNumber()} - ${info1[2].toNumber()} `
    );

    expect(info1[1].toNumber()).to.equal(0);
    expect(info1[2].toNumber()).to.equal(totNFTs / 2 - 1);

    const info2 = await mboxContract.getSubInfos(evenAllocContract.address); // 5 seconds lockup period

    console.log(
      `\tEvenAllocation token range : ${info2[1].toNumber()} - ${info2[2].toNumber()} `
    );

    expect(info2[1].toNumber()).to.equal(totNFTs / 2);
    expect(info2[2].toNumber()).to.equal(totNFTs - 1);
  });
});
