import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumber, BigNumberish } from "ethers";
import { parseUnits } from "ethers/lib/utils";
import fs from "fs";
import { ethers, waffle } from "hardhat";
import moment from "moment/moment";
import {
  ERC721Token,
  MysteryBox,
  Subscription,
  WhiteListNFT,
} from "../typechain";
import { chainId, overrides, verifyCode, witnetAddress } from "./constants";

const STAKING_PAYMENTS = [30, 10, 10, 3, 4, 15, 200, 30, 10, 80, 33];

let keyContract: ERC721Token;
let keyAddress: string;

let mboxContract: MysteryBox;
let mboxAddress: string;

const nWhitelist = 2;
const andor = false;
const whitelistContracts: WhiteListNFT[] = [];
const whitelistAddrs: string[] = [];
const whitelistTypes: boolean[] = [];

// 테스트 파라미터 >>>
const mboxPrice = ethers.utils.parseUnits("1.0", "ether");

const ratePriceEth = "2.0"; // 비례 배분 가격
const evenPriceEth = "0.1"; // 균등 배분 가격
const nUsers = 11; // 청약 참여자 수
const allocNFTs: number[] = [];
const refunds: BigNumber[] = [];
const balancesBefore: BigNumber[] = [];
const balancesAfter: BigNumber[] = [];
let totNFTs = 0; // 총 판매 NFT 수

const launch = moment().unix() + 60; // 2 Minutes
// <<<

let subscriptionContract: Subscription;
let signers: SignerWithAddress[] = [];
let payments: BigNumber[] = [];

function delay(interval: number) {
  return it("should delay", (done) => {
    setTimeout(() => done(), interval);
  }).timeout(interval + 100); // The extra 100ms should guarantee the test will not fail due to exceeded timeout
}

function calculation(x: number, y: number): number {
  return x * parseFloat(ratePriceEth) + y * parseFloat(evenPriceEth);
}

function generateRandom(maxLimit = 10) {
  let rand = Math.random() * maxLimit;
  rand = Math.floor(rand); // 99
  return rand;
}

describe("Subscription Test on Hardhat", function () {
  it("Get signer address", async function () {
    signers = await ethers.getSigners();
    for (let i = 1; i < nUsers; i++) {
      await signers[0].sendTransaction({
        to: signers[i].address,
        value: ethers.utils.parseEther((STAKING_PAYMENTS[i] + 1).toString()),
      });
    }
  });

  it("Deploy an ERC-721 Key contract", async function () {
    const ERC721Token = await ethers.getContractFactory("ERC721Token");
    const constructorArguments = ["Mystery Box Key", "KEY"] as const;

    keyContract = await ERC721Token.deploy(...constructorArguments);
    await keyContract.deployed();

    keyAddress = keyContract.address;

    await verifyCode({ address: keyAddress, constructorArguments });

    expect(await keyContract.symbol()).to.equal("KEY");
    // console.log("Deployed Key contract : ", keyAddress);
  });

  it("Deploy MysteryBox Contract", async function () {
    const mysteryBox = await ethers.getContractFactory("MysteryBox");
    const constructorArguments = [
      "Mystery Box",
      "MBX",
      keyAddress, // use Subscription
      "0x0000000000000000000000000000000000000000", // Klay
      signers[0].address,
      signers[1].address,
      [launch, 0, mboxPrice, 50] as BigNumberish[], // Set by Subscription Contract
      witnetAddress,
    ] as const;

    mboxContract = await mysteryBox.deploy(...constructorArguments);
    await mboxContract.deployed();

    mboxAddress = mboxContract.address;

    await verifyCode({ address: mboxAddress, constructorArguments });

    expect(await mboxContract.symbol()).to.equal("MBX");
    console.log("\tDeployed MysteryBox Contract : ", mboxAddress);
  });

  it("Set mystery box to Key contract", async function () {
    const tx = await keyContract.setMysteryBox(mboxAddress);
    // wait until the transaction is mined
    await tx.wait();
  });

  it("Register MysteryBox Items", async function () {
    const uris = [
      "https://ipfs.io/ipfs/QmeJL6hGSHvcxiFJyuwFSG1Yv2MWLsnDKyeQheQdzwnEo3",
      // "https://ipfs.io/ipfs/QmXbw7RZwyLDa1q4X9N2RwyEEvjDVCc2L6pJ1oiS4Ehf9S",
      // "https://ipfs.io/ipfs/QmV5FRQZLogf8JxGCn4tymPAsQoH74P52WXyYHFgQGi873",
    ];
    // const amounts = [10, 10, 10]; // totalSupply = 30
    const amounts = [100]; // totalSupply = 30
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

  it("Set Hard Cap - Subscription", async function () {
    const tx = await keyContract.setHardCap(
      totNFTs,
      "https://ipfs.io/ipfs/QmeJL6hGSHvcxiFJyuwFSG1Yv2MWLsnDKyeQheQdzwnEo3"
    );
    await tx.wait();

    const hardCap = await keyContract.hardCap();

    expect(hardCap.toNumber()).to.be.equal(totNFTs);
  });

  it("Deploy WhitelistNFT Contracts", async function () {
    const whiteList = await ethers.getContractFactory("WhiteListNFT");
    for (let i = 0; i < nWhitelist; i++) {
      const constructorArguments = [
        "WhiteList Test",
        "TST",
        true,
        i % 2 === 0,
      ] as const;

      whitelistContracts[i] = await whiteList.deploy(...constructorArguments);
      await whitelistContracts[i].deployed();

      await verifyCode({
        address: whitelistContracts[i].address,
        constructorArguments,
      });

      expect(whitelistContracts[i].address !== "");
      console.log(
        "\tDeployed WhitelistNFT Contract : ",
        whitelistContracts[i].address
      );

      whitelistAddrs.push(whitelistContracts[i].address);
      whitelistTypes.push(i % 2 === 0);
    }
  });

  it("Add white List", async function () {
    const list = [];

    if (chainId === 1001) {
      // eslint-disable-next-line node/no-unsupported-features/node-builtins
      const jsonData = await fs.promises.readFile("./list.data", "utf8");
      const allList = JSON.parse(jsonData);
      for (let i = 0; i < nUsers; i++) {
        list.push(allList[i]);
      }
    } else {
      for (let i = 0; i < nUsers; i++) {
        list.push(signers[i].address);
      }
      await fs.writeFileSync("./list.data", JSON.stringify(list));
    }
    // console.log(list);

    for (let i = 0; i < nWhitelist; i++) {
      const tx = await whitelistContracts[i].addWhitelist(list, 0);
      const receipt = await tx.wait();
      console.log("\taddWhitelist Hash : ", receipt.transactionHash);

      // @ts-ignore
      expect(receipt?.events[0].args[1]).to.be.equal(nUsers);
      // @ts-ignore
      const target = receipt?.events[0].args[0];
      expect(target).to.be.equal(0);
    }
  });

  it("BatchMint to whitelist", async function () {
    for (let i = 0; i < nWhitelist; i++) {
      const tx = await whitelistContracts[i].safeBatchMintToWhitelist(
        "https://ipfs.io/ipfs/QmSNUNTmgoUTomg7kY55Pb7YQoY8tWw3AGC2gozCLtApW1",
        0
      );
      const receipt = await tx.wait();
      console.log(
        "\tsafeBatchMintToWhitelist Hash : ",
        receipt.transactionHash
      );

      const totalSupply = await whitelistContracts[i].totalSupply();
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
    configs.push(totNFTs);
    configs.push(100); // 50%
    configs.push(25); // 2.5%
    configs.push(50); // 5%
    configs.push(launch);
    configs.push(launch + 90);

    const constructorArguments = [
      configs,
      "0x0000000000000000000000000000000000000000",
      payment.address,
      treasury.address,
      mboxAddress,
      whitelistAddrs,
      whitelistTypes,
      andor,
      witnetAddress,
    ] as const;

    subscriptionContract = await subscription.deploy(...constructorArguments);
    await subscriptionContract.deployed();

    await verifyCode({
      address: subscriptionContract.address,
      constructorArguments,
    });

    expect(subscriptionContract.address !== "");
    console.log(
      "\tDeployed Subscription Contract : ",
      subscriptionContract.address
    );

    for (let i = 0; i < nWhitelist; i++) {
      await whitelistContracts[i].setStaking(subscriptionContract.address);
    }
  });

  it("Set Subscription Contract to MysteryBox", async function () {
    // Post-Mint Case
    const tx = await mboxContract.setSubscription(
      subscriptionContract.address,
      2,
      totNFTs
    );
    // wait until the transaction is mined
    await tx.wait();

    const subscription = await mboxContract.subInfos(0);
    expect(subscription[0]).to.equal(subscriptionContract.address);
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

  it("Set whitelist", async function () {
    const andor: boolean = false;
    const tx = await subscriptionContract.setWhiteList(
      whitelistAddrs,
      whitelistTypes,
      andor
    );
    await tx.wait();
  });

  it("Set Approval to Whitelist", async function () {
    for (let i = 0; i < nWhitelist; i++) {
      for (let j = 0; j < nUsers; j++) {
        const approveTx = await whitelistContracts[i]
          .connect(signers[j])
          .setApprovalForAll(subscriptionContract.address, true);
        // wait until the transaction is mined
        await approveTx.wait();

        const approve = await whitelistContracts[i].isApprovedForAll(
          signers[j].address,
          subscriptionContract.address
        );
        expect(approve, "true");
      }
    }
  });

  it("Prepare randomness", async function () {
    const value = parseUnits("26250000000000000", "wei").toString();
    const witnetTx = await subscriptionContract.requestRandomNumber({
      value: value,
    });
    const witnetTx2 = await mboxContract.requestRandomNumber({
      value: value,
    });

    // wait until the transaction is mined
    await witnetTx.wait();
    await witnetTx2.wait();

    expect(await subscriptionContract.latestRandomizingBlock()).not.to.be.equal(
      BigNumber.from(0)
    );
    expect(await mboxContract.latestRandomizingBlock()).not.to.be.equal(
      BigNumber.from(0)
    );
  });

  // Wait for Launch time reached
  delay(60000);

  it("Staking", async function () {
    for (let i = 0; i < nUsers; i++) {
      // const payment =
      //   generateRandom() * parseFloat(ratePriceEth) +
      //   // generateRandom() * parseFloat(evenPriceEth) +
      //   Math.max(parseFloat(ratePriceEth), parseFloat(evenPriceEth)); // Minimum staking = choose the bigger both two prices
      // // const payment = await subscriptionContract.getLeastFund();

      const payment = STAKING_PAYMENTS[i];
      payments.push(ethers.utils.parseUnits(payment.toString(), "ether"));

      const applyTx = await subscriptionContract
        .connect(signers[i])
        .stakingEth({
          value: ethers.utils.parseUnits(payment.toString(), "ether"),
        });

      const txReceipt = await applyTx.wait();

      // console.log("--->", txReceipt);
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
      expect(txReceipt?.events[eventIx].args[2] ?? "0").to.equal(payments[i]);
    }

    for (let i = 0; i < nWhitelist; i++) {
      if (!andor && i > 0) break;
      const balance = await whitelistContracts[i].balanceOf(
        subscriptionContract.address
      );
      expect(balance).to.equal(nUsers);
    }
  });

  let addAmount: number;
  const tIndex = 1;

  it("Staking More", async function () {
    addAmount =
      generateRandom() * parseFloat(ratePriceEth) +
      generateRandom() * parseFloat(evenPriceEth) +
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

    // 11th unstake all
    const tx2 = await subscriptionContract
      .connect(signers[2])
      .unStaking(payments[2]);
    await tx2.wait();
    payments[2] = BigNumber.from(0);
  });

  let totalFund: BigNumber = ethers.utils.parseUnits("0", "ether");
  let rateAmount: BigNumber = ethers.utils.parseUnits("0", "ether");

  it("Get least fund to get a key", async function () {
    totalFund = await subscriptionContract.totalFund();
    console.log("\tTotal Fund  = ", totalFund);

    rateAmount = await subscriptionContract.rateAmount();
    console.log("\tRate Amount = ", rateAmount);

    const leastFund = await subscriptionContract.getLeastFund();
    console.log("\tLeast Fund  = ", leastFund);
    expect(parseFloat(ethers.utils.formatEther(leastFund))).to.gt(0);
  });

  // it("Allocation", async function () {
  //   const allocTx = await subscriptionContract.allocation(overrides);
  //   const txReceipt = await allocTx.wait();
  //
  //   // console.log(txReceipt);
  //   const gasUsed: BigNumber = txReceipt.cumulativeGasUsed.mul(
  //     // ethers.utils.parseUnits("250", "gwei")  // Klaytn의 경우
  //     txReceipt.effectiveGasPrice // 9 gwei 로 나옴
  //   );
  //   // console.log(txReceipt.cumulativeGasUsed, txReceipt.effectiveGasPrice);
  //   // console.log(ethers.utils.formatEther(gasUsed));
  //
  //   const status = await subscriptionContract.allocStatus();
  //   expect(status).to.equal(true);
  // });
  //
  // it("Check Allocation Result", async function () {
  //   // const totalFund = await subscriptionContract.totalFund();
  //   // console.log("= Total Funds =>", totalFund);
  //
  //   // const evenAmount = await subscriptionContract.evenAmount();
  //   // console.log("= even amount =>", evenAmount);
  //
  //   let booking;
  //   let nNFTs = 0;
  //   let totFunds = 0;
  //   for (let i = 0; i < nUsers; i++) {
  //     // Caution : Skip index 0 in the smart contract
  //     booking = await subscriptionContract.booking(i + 1);
  //
  //     const cost: number = calculation(
  //       booking.rateAlloc.toNumber(),
  //       booking.evenAlloc.toNumber()
  //     );
  //
  //     allocNFTs.push(booking.totalAlloc.toNumber());
  //     refunds.push(
  //       payments[i].sub(ethers.utils.parseUnits(cost.toString(), "ether"))
  //     );
  //
  //     console.log(
  //       `\tUser #${i + 1} ${ethers.utils.formatEther(
  //         payments[i]
  //       )} : ${booking.totalAlloc.toNumber()} = ${booking.rateAlloc.toNumber()} + ${booking.evenAlloc.toNumber()} = ${cost} Klay`
  //     );
  //     // console.log(booking);
  //
  //     expect(cost).to.be.at.most(
  //       parseFloat(ethers.utils.formatEther(payments[i]))
  //     );
  //
  //     nNFTs = nNFTs + booking.totalAlloc.toNumber();
  //     totFunds = totFunds + parseFloat(ethers.utils.formatEther(payments[i]));
  //   }
  //
  //   console.log(
  //     `\tTotal NFTs = ${totNFTs}, Total Fund = ${totFunds}, Left NFTs = ${
  //       totNFTs - nNFTs
  //     }`
  //   );
  // });

  // it("claim before Claim Time", async function () {
  //   await expect(
  //     subscriptionContract.connect(signers[0]).claim()
  //   ).to.be.revertedWith("Claim time is not yet reached");
  // });

  // it("Wait for release time reached... about 10 seconds", async function () {
  //   // Just for test purpose
  //   const claimTx = await mboxContract.setReleaseForTest(); // 5 seconds lockup period
  //   // wait until the transaction is mined
  //   await claimTx.wait();
  // });

  delay(90000); //  7 Seconds

  // This Test is possible only on the real chain.
  it("Claim after Claim Time", async function () {
    const provider = waffle.provider;

    for (let i = 0; i < nUsers; i++) {
      if (payments[i].gt(BigNumber.from(0))) {
        console.log("=========>", i);
        const amount = rateAmount.mul(payments[i]).div(totalFund);
        console.log("\t===> ", amount);

        const beforeBalance: BigNumber = await provider.getBalance(
          signers[i].address
        );
        balancesBefore.push(beforeBalance);

        const before: BigNumber = await provider.getBalance(
          subscriptionContract.address
        );

        const tx = await subscriptionContract.connect(signers[i]).claim();
        const receipt = await tx.wait();
        // @ts-ignore
        // console.log("===> ", receipt.events);

        const afterBalance: BigNumber = await provider.getBalance(
          signers[i].address
        );
        balancesAfter.push(afterBalance);

        const after: BigNumber = await provider.getBalance(
          subscriptionContract.address
        );

        const gap = before.sub(after);
        // console.log(before, " - ", after, " = ", gap);
        // console.log(payments[i]);

        expect(gap).to.deep.equal(payments[i]);
      }
    }
  });

  it("Check Claim Result", async function () {
    // Check refunded whitelist NFTs
    for (let i = 0; i < nWhitelist; i++) {
      if (!andor && i === 1) break;
      for (let j = 0; j < nUsers; j++) {
        if (payments[j].gt(BigNumber.from(0))) {
          const balance = await whitelistContracts[i].balanceOf(
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
    }

    // Check refunded klays
    // for (let i = 0; i < nUsers; i++) {
    //   const zero: BigNumber = ethers.utils.parseUnits("0", "ether");
    //   if (refunds[i].eq(zero)) {
    //     // gas consumed for claim
    //     expect(balancesBefore[i].sub(balancesAfter[i])).to.gt(zero);
    //   } else {
    //     // gas consumed for claim but balance increased by refunded klay
    //     expect(balancesAfter[i].sub(balancesBefore[i])).to.gt(zero);
    //   }
    // }

    for (let i = 0; i < nUsers; i++) {
      if (payments[i].gt(BigNumber.from(0))) {
        const ix = await subscriptionContract.depositIndex(signers[i].address);
        const booking = await subscriptionContract.booking(ix);
        console.log("\t----->", booking.totalAlloc.toNumber());
        allocNFTs.push(booking.totalAlloc.toNumber());
      } else {
        allocNFTs.push(0);
      }
    }
    // Check keys sent to me
    for (let i = 0; i < nUsers; i++) {
      if (payments[i].gt(BigNumber.from(0))) {
        const balance = await keyContract.balanceOf(signers[i].address);
        console.log("\t Key Balance = ", balance);
        expect(balance).to.equal(allocNFTs[i]);
      }
    }
  });

  it("Claim items", async function () {
    for (let i = 0; i < nUsers; i++) {
      const balance = await keyContract.balanceOf(signers[i].address);
      // console.log("---> ", balance);

      if (balance.toNumber() > 0) {
        let tx = await keyContract
          .connect(signers[i])
          .setApprovalForAll(mboxAddress, true);
        await tx.wait();

        tx = await mboxContract
          .connect(signers[i])
          .claim(signers[i].address, balance, overrides);
        await tx.wait();
      }
    }
  });

  // it("Get booking data", async function () {
  //   const booking = await subscriptionContract.getBooking();
  //   // console.log("Booking  = ", booking);
  // });

  it("Get Win Count", async function () {
    for (let i = 0; i < nUsers; i++) {
      if (payments[i].gt(BigNumber.from(0))) {
        const myWin = await subscriptionContract.connect(signers[i]).getMyWin();
        console.log("\t==> ", myWin);
        // console.log("Booking  = ", booking);
      }
    }
  });
});
