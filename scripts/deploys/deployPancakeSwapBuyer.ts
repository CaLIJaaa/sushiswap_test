import { ethers } from "ethers";
import * as fs from "fs";
import * as path from "path";
import dotenv from 'dotenv';
import { tenderly } from "hardhat";
dotenv.config();

const contractPath = path.resolve(__dirname, "../../artifacts/contracts/PancakeSwapBuyer.sol/PancakeSwapBuyer.json");
const contractJson = JSON.parse(fs.readFileSync(contractPath, "utf8"));
const { abi, bytecode } = contractJson;

async function main() {
    const provider = new ethers.JsonRpcProvider(process.env.TENDERLY_RPC_URL);

    const privateKey = process.env.PRIVATE_KEY; 
    if (!privateKey) throw new Error("PRIVATE_KEY not found in .env");
    const wallet = new ethers.Wallet(privateKey, provider);

    const contractFactory = new ethers.ContractFactory(abi, bytecode, wallet);

    const contract = await contractFactory.deploy();

    await contract.waitForDeployment();
    
    await tenderly.verify({
        name: 'contracts/PancakeSwapBuyer.sol:PancakeSwapBuyer',
        address: await contract.getAddress()
    });

    console.log(`Contract deployed at address: ${contract.target}`);
}

main().catch((error) => {
    console.error("Error deploying contract:", error);
    process.exit(1);
});