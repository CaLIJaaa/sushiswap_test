import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import dotenv from "dotenv";
import * as tenderly from "@tenderly/hardhat-tenderly";

tenderly.setup({ automaticVerifications: false });

dotenv.config();

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.28",
    settings: {
      viaIR: true,
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    virtualMainnet: {
      url: `${process.env.TENDERLY_RPC_URL}`,
      chainId: 1
    },
  },
  tenderly: {
    project: "tenderly-tests",
    username: "CaLIJaaa",
  },
};

export default config;
