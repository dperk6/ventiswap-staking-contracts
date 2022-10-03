// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { ethers, run } from "hardhat";
import { approve, getBalance, makeSwap } from "./utils";

const VST = "0xb7C2fcD6d7922eddd2A7A9B0524074A60D5b472C";
const WETH = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";

async function main() {
    const signers = await ethers.getSigners();

    const NFT = await ethers.getContractFactory("TestNFT");
    const Stake = await ethers.getContractFactory("VentiHeadzStake");

    const nft = await NFT.deploy();
    await nft.deployed();

    const stake = await Stake.deploy(nft.address);
    await stake.deployed();

    await makeSwap(signers[0], [WETH, VST], "5.0");
    const tokenBalance = await getBalance(signers[0].address, VST);
    await approve(signers[0], stake.address, VST);

    await stake.addRewardTokens(tokenBalance.toString());
    await stake.setActive();

    for (let i = 0; i < 5; i++) {
        await nft.connect(signers[i]).mint();
        await nft.connect(signers[i]).mint();

        await nft.connect(signers[i]).setApprovalForAll(stake.address, true);
    }

    await stake.connect(signers[0]).stakeToken(2);

    await ethers.provider.send('evm_increaseTime', [2628000 * 14]);
    await ethers.provider.send('evm_mine', []);

    await run('node');
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
