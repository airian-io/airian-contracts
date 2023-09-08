import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumber, BigNumberish } from "ethers";
import { formatEther, parseEther, parseUnits } from "ethers/lib/utils";
import fs from "fs";
import { ethers, waffle } from "hardhat";
import moment from "moment";
import {
  ERC721Token,
  EvenAllocation,
  MysteryBox,
  WhiteListNFT,
} from "../typechain";
import { chainId, overrides, verifyCode, witnetAddress } from "./constants";

let keyContract: ERC721Token;
let keyAddress: string;

let mboxContract: MysteryBox;
let mboxAddress: string;

const nWhitelist = 2;
const andor = true;
const whitelistContracts: WhiteListNFT[] = [];
const whitelistAddrs: string[] = [];
const whitelistTypes: boolean[] = [];

// 테스트 파라미터 >>>
const mboxPrice = ethers.utils.parseUnits("1.0", "ether");

const priceEth = "1.0"; // 티켓 가격
// const nUsers = 1000; // 청약 참여자 수
const nUsers = 400; // 청약 참여자 수
const allocNFTs: number[] = [];
const refunds: BigNumber[] = [];
let totNFTs = 0; // 총 판매 NFT 수
const maxTicket = 5;
const perTicket = 1;
const launch = moment().unix() + 60; // 1 Minutes
let allocated: number[] = [];
// <<<

let evenAllocContract: EvenAllocation;
let signers: SignerWithAddress[] = [];
const payments: BigNumber[] = [];

function delay(interval: number) {
  return it("should delay", (done) => {
    setTimeout(() => done(), interval);
  }).timeout(interval + 100); // The extra 100ms should guarantee the test will not fail due to exceeded timeout
}

function calculation(x: number): number {
  return x * parseFloat(priceEth);
}

describe("EvenAllocation Test on Hardhat", function () {
  it("Get signer address", async function () {
    signers = await ethers.getSigners();
    for (let i = 1; i < nUsers; i++) {
      await signers[0].sendTransaction({
        to: signers[i].address,
        value: ethers.utils.parseEther("0.2"),
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
    const mysteryBoxWitNet = await ethers.getContractFactory("MysteryBox");
    const constructorArguments = [
      "Mystery Box",
      "MBX",
      keyAddress, // use Subscription
      "0x0000000000000000000000000000000000000000",
      signers[0].address,
      signers[1].address,
      [0, 0, mboxPrice, 50] as BigNumberish[], // Set by Subscription Contract
      // [launch, 0, mboxPrice, 50], // Set by Subscription Contract
      witnetAddress,
    ] as const;

    mboxContract = await mysteryBoxWitNet.deploy(...constructorArguments);
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

  it("Set Hard Cap - Even allocation", async function () {
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
    signers = await ethers.getSigners();

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
        0,
        overrides
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

  it("Deploy EvenAllocation Contract", async function () {
    const [payment, treasury] = await ethers.getSigners();
    const price: BigNumber = ethers.utils.parseUnits(priceEth, "ether");
    const evenAllocation = await ethers.getContractFactory("EvenAllocation");
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
    configs.push(totNFTs);
    configs.push(25); // 2.5%
    configs.push(50); // 5%
    configs.push(launch);
    configs.push(launch + 60);
    configs.push(maxTicket);
    configs.push(perTicket);

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

    evenAllocContract = await evenAllocation.deploy(...constructorArguments);
    await evenAllocContract.deployed();

    await verifyCode({
      address: evenAllocContract.address,
      constructorArguments,
    });

    for (let i = 0; i < nWhitelist; i++) {
      await whitelistContracts[i].setStaking(evenAllocContract.address);
    }

    expect(evenAllocContract.address !== "");
    console.log(
      "\tDeployed EvenAllocation Contract : ",
      evenAllocContract.address
    );
  });

  it("Set Subscription Contract to MysteryBox", async function () {
    // Post-Mint Case
    const tx = await mboxContract.setSubscription(
      evenAllocContract.address,
      1,
      totNFTs
    );
    // wait until the transaction is mined
    await tx.wait();

    const subscription = await mboxContract.subInfos(0);
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
      const approveTxs = [];
      for (let j = 0; j < nUsers; j++) {
        approveTxs.push(
          await whitelistContracts[i]
            .connect(signers[j])
            .setApprovalForAll(evenAllocContract.address, true)
        );
      }

      for (let j = 0; j < nUsers; j++) {
        // wait until the transaction is mined
        await approveTxs[j].wait();

        const approve = await whitelistContracts[i].isApprovedForAll(
          signers[j].address,
          evenAllocContract.address
        );
        expect(approve, "true");
      }
    }
  });

  // it("Prepare randomness", async function () {
  //   const value = parseUnits("26250000000000000", "wei").toString();
  //   const witnetTx = await evenAllocContract.requestRandomNumber({
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

  function generateRandom(maxLimit = maxTicket - 1) {
    let rand = Math.random() * maxLimit;
    rand = Math.floor(rand); // 99
    return rand;
  }

  // Wait for Launch time reached
  delay(60000); //  1 Minutes

  it("Buying Tickets", async function () {
    const chargeTxs = [];
    const nTicketsList = [];
    for (let i = 0; i < nUsers; i++) {
      const nTickets = generateRandom() + 1;
      nTicketsList.push(nTickets);

      const payment = parseEther((nTickets * parseFloat(priceEth)).toString());
      payments.push(payment);

      const balance = await signers[i].getBalance();
      const deficiency = payment.sub(balance);
      if (deficiency.gt(0)) {
        const value = deficiency.add(parseEther("0.3"));
        chargeTxs.push(
          await signers[0].sendTransaction({ to: signers[i].address, value })
        );
      }
    }

    await Promise.all(chargeTxs.map((tx) => tx.wait()));

    const applyTxs = [];
    for (let i = 0; i < nUsers; i++) {
      const nTickets = nTicketsList[i];
      const payment = payments[i];
      applyTxs.push(
        await evenAllocContract
          .connect(signers[i])
          .buyTicketEth(nTickets, { value: payment })
      );
    }

    await Promise.all(applyTxs.map((tx) => tx.wait()));

    for (let i = 0; i < nWhitelist; i++) {
      if (!andor && i > 0) break;
      const balance = await whitelistContracts[i].balanceOf(
        evenAllocContract.address
      );
      expect(balance).to.equal(nUsers);
    }

    // const ticketData = await evenAllocContract.getTicketData();
    // console.log("\tticketData = ", ticketData);
  });

  it("Get sold ticket count", async function () {
    const totalSold = await evenAllocContract.getTicketCount();
    console.log("\tSold Tickets = ", totalSold);

    // expect(available).to.equal(10);
  });

  // it("Allocation", async function () {
  //   const allocTx = await evenAllocContract.allocation(overrides);
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
  //   const status = await evenAllocContract.allocStatus();
  //   expect(status).to.equal(true);
  // });
  //
  // it("Check Allocation Result", async function () {
  //   // const totalFund = await evenAllocContract.totalFund();
  //   // console.log("= Total Funds =>", totalFund);
  //
  //   // const evenAmount = await evenAllocContract.evenAmount();
  //   // console.log("= even amount =>", evenAmount);
  //
  //   let booking;
  //   let nNFTs = 0;
  //
  //   for (let i = 0; i < nUsers; i++) {
  //     // Caution : Skip index 0 in the smart contract
  //     booking = await evenAllocContract.booking(i + 1);
  //
  //     const cost: number = calculation(booking.allocated.toNumber());
  //
  //     allocNFTs.push(booking.allocated.toNumber());
  //     refunds.push(
  //       payments[i].sub(ethers.utils.parseUnits(cost.toString(), "ether"))
  //     );
  //
  //     allocated[i] = booking.allocated.toNumber();
  //
  //     console.log(
  //       `\tUser #${i + 1} ${ethers.utils.formatEther(
  //         payments[i]
  //       )} : ${booking.allocated.toNumber()} = ${cost} Klay`
  //     );
  //     // console.log(booking);
  //
  //     expect(cost).to.be.at.most(
  //       parseFloat(ethers.utils.formatEther(payments[i]))
  //     );
  //
  //     nNFTs = nNFTs + booking.allocated.toNumber();
  //   }
  //
  //   console.log(`\tTotal NFTs = ${totNFTs}, Left NFTs = ${totNFTs - nNFTs}`);
  // });

  // it("claim before Claim Time", async function () {
  //   await expect(
  //     evenAllocContract.connect(signers[0]).claim()
  //   ).to.be.revertedWith("Claim time is not yet reached");
  // });

  // it("Wait for release time reached... about 10 seconds", async function () {
  //   // Just for test purpose
  //   const claimTx = await mboxContract.setReleaseForTest(); // 5 seconds lockup period
  //   // wait until the transaction is mined
  //   await claimTx.wait();
  // });

  delay(60000); //  1 Minute

  it("Prepare randomness", async function () {
    const value = parseUnits("26250000000000000", "wei").toString();
    const witnetTx = await evenAllocContract.requestRandomNumber({
      value: value,
    });
    const witnetTx2 = await mboxContract.requestRandomNumber({
      value: value,
    });

    // wait until the transaction is mined
    await witnetTx.wait();
    await witnetTx2.wait();

    expect(await evenAllocContract.latestRandomizingBlock()).not.to.be.equal(
      BigNumber.from(0)
    );
    expect(await mboxContract.latestRandomizingBlock()).not.to.be.equal(
      BigNumber.from(0)
    );
  });

  // This Test is possible only on the real chain.
  it("Claim after Claim Time", async function () {
    const provider = waffle.provider;

    const beforeBalance = await provider.getBalance(evenAllocContract.address);

    const claimTxs = [];
    for (let i = 0; i < nUsers; i++) {
      claimTxs.push(
        await evenAllocContract
          .connect(signers[i])
          .claim({ gasLimit: 1_000_000 })
      );
    }

    await Promise.all(claimTxs.map((tx) => tx.wait()));

    const afterBalance = await provider.getBalance(evenAllocContract.address);
    const gap = beforeBalance.sub(afterBalance);

    const totalPayments = payments.reduce(
      (s, p) => s.add(p),
      BigNumber.from(0)
    );
    expect(gap).to.deep.equal(totalPayments);
  });

  it("Check Claim Result", async function () {
    // Check refunded whitelist NFTs
    for (let i = 0; i < nWhitelist; i++) {
      if (!andor && i === 1) break;
      for (let j = 0; j < nUsers; j++) {
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

    let booking;
    for (let i = 0; i < nUsers; i++) {
      // Caution : Skip index 0 in the smart contract
      booking = await evenAllocContract.booking(i + 1);
      allocNFTs.push(booking.allocated.toNumber());
    }

    // Check minted items to me
    let sum: BigNumber = BigNumber.from(0);
    let multi = 0;
    for (let i = 0; i < nUsers; i++) {
      const balance = await keyContract.balanceOf(signers[i].address);
      console.log("\t Key Balance = ", balance);
      if (balance.toNumber() > 1) multi++;
      sum = sum.add(balance);
      expect(balance).to.equal(allocNFTs[i] * perTicket);
    }
    console.log("\t Total = ", sum.toNumber(), multi);
  });

  it("Claim items", async function () {
    const approveTxs = [];
    for (let i = 0; i < nUsers; i++) {
      const balance = await keyContract.balanceOf(signers[i].address);

      if (balance.toNumber() > 0) {
        approveTxs.push(
          await keyContract
            .connect(signers[i])
            .setApprovalForAll(mboxAddress, true)
        );
      }
    }

    await Promise.all(approveTxs.map((tx) => tx.wait()));

    const claimTxs = [];
    for (let i = 0; i < nUsers; i++) {
      const balance = await keyContract.balanceOf(signers[i].address);

      console.log(
        `claim[${i}], address=${
          signers[i].address
        }, balance=${balance.toString()}`
      );

      if (balance.toNumber() > 0) {
        claimTxs.push(
          await mboxContract
            .connect(signers[i])
            .claim(signers[i].address, balance, { gasLimit: 1_000_000 })
        );
      }
    }

    await Promise.all(claimTxs.map((tx) => tx.wait()));
  });
});
