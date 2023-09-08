import { network, run as hreRun } from "hardhat";
import { TaskArguments } from "hardhat/types";

const VERIFY_CODE = true;

export const chainId = network.config.chainId;

export const witnetAddress =
  chainId === 203
    ? "0x95250dFC15CC25d744c33cC6B458CB3FB6B1Ce3a" // TMP WitNet Randomness Contract
    : chainId === 1001
    ? "0xB4B2E2e00e9d6E5490d55623E4F403EC84c6D33f" // Baobab WitNet Randomness Contract
    : "";

export const overrides = {
  gasLimit: 400_000_000,
  // gasPrice: 9000000000,
};

export const verifyCode = async (
  taskArguments: TaskArguments
): Promise<any> => {
  if (VERIFY_CODE) {
    // eslint-disable-next-line no-unreachable-loop
    for (let i = 0; i < 3; i++) {
      try {
        return await hreRun("verify:verify", taskArguments);
      } catch (e) {
        console.log(e);
      }
    }
  }
};
