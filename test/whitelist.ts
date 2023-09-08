import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import * as fs from "fs";
import { ethers, network } from "hardhat";
import { WhiteListNFT } from "../typechain";
import { overrides, verifyCode } from "./constants";

let whitelistContract: WhiteListNFT;
let signers: SignerWithAddress[] = [];
// For klaytn, ~480 is the maximum of safeBatchMinToWhitelist
// const nTest = 450;
const nTest = 400;
let target: number;
let owner: string;

const networkName = network.name;
const chainId = network.config.chainId;

function delay(interval: number) {
  return it("should delay", (done) => {
    setTimeout(() => done(), interval);
  }).timeout(interval + 100); // The extra 100ms should guarantee the test will not fail due to exceeded timeout
}

describe("WhiteListNFT Test", function () {
  it("Deploy whitelist nft contract", async function () {
    const whiteList = await ethers.getContractFactory("WhiteListNFT");
    const constructorArguments = [
      "WhiteList Test",
      "TST",
      true,
      false,
    ] as const;

    whitelistContract = await whiteList.deploy(...constructorArguments);
    await whitelistContract.deployed();

    await verifyCode({
      address: whitelistContract.address,
      constructorArguments,
    });

    expect(whitelistContract.address !== "");
    console.log("Contract Address : ", whitelistContract.address);
  });

  it("Add white list", async function () {
    signers = await ethers.getSigners();
    owner = signers[0].address;

    const list = [];

    if (chainId === 1001) {
      // eslint-disable-next-line node/no-unsupported-features/node-builtins
      const jsonData = await fs.promises.readFile("./list.data", "utf8");
      const allList = JSON.parse(jsonData);
      for (let i = 0; i < nTest; i++) {
        list.push(allList[i]);
      }
    } else {
      for (let i = 0; i < nTest; i++) {
        list.push(signers[i].address);
      }
      await fs.writeFileSync("./list.data", JSON.stringify(list));
    }

    // console.log(list);
    const tx = await whitelistContract.addWhitelist(list, 0);
    const receipt = await tx.wait();
    console.log("addWhitelist Hash : ", receipt.transactionHash);

    // @ts-ignore
    expect(receipt?.events[0].args[1]).to.be.equal(nTest);

    // @ts-ignore
    target = receipt?.events[0].args[0];
    expect(target).to.be.equal(0);
  });

  /*
   * TODO
   *  - hardhat 테스트로는 nTest 37 까지만 성공, 이후로는 실패
   *  - Remix에서는 40 성공함. https://baobab.scope.klaytn.com/tx/0xe935e3f5e959b524c5f01b6b4e5f6b6df818042af9fe6b47b3c9a42bda365cc0?tabId=nftTransfer
   *  > 왜 그렇까 ?
   *  > Klaytn은 Transaction 실행 시간 관리를 위해서 Transaction 당 Computation Cost(연산비용)에 제한을 100,000,000으로 설정
   *  > 참고 링크 : https://forum.klaytn.foundation/t/erropcodecntlimitreached/676
   */
  it("BatchMint to whitelist", async function () {
    const tx = await whitelistContract.safeBatchMintToWhitelist(
      "https://ipfs.io/ipfs/QmSNUNTmgoUTomg7kY55Pb7YQoY8tWw3AGC2gozCLtApW1",
      0,
      overrides
    );
    const receipt = await tx.wait();
    console.log("safeBatchMintToWhitelist Hash : ", receipt.transactionHash);

    const totalSupply = await whitelistContract.totalSupply();
    expect(totalSupply).to.be.equal(nTest);
  });

  it("Transferable test", async function () {
    if (chainId !== 1001) {
      await expect(
        whitelistContract.transferFrom(owner, signers[1].address, 0)
      ).to.be.revertedWith("soulbound NFT");
    }
  });
});
