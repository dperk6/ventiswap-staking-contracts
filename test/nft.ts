import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumber } from "ethers";
import { ethers, network } from "hardhat";
import { approve, getBalance, makeSwap } from "../scripts/utils";
import { TestNFT, VentiHeadzStake } from "../typechain";

const VST = "0xb7C2fcD6d7922eddd2A7A9B0524074A60D5b472C";
const WETH = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";

describe("Ventiheadz Staking", function () {
    let stake: VentiHeadzStake;
    let nft: TestNFT;
    let signers: SignerWithAddress[];
    let ids: {account: string, id: number}[] = [];

    this.beforeEach(async () => {
        const NFT = await ethers.getContractFactory("TestNFT");
        const Stake = await ethers.getContractFactory("VentiHeadzStake");

        signers = await ethers.getSigners();

        nft = await NFT.deploy();
        await nft.deployed();

        stake = await Stake.deploy(nft.address);
        await stake.deployed();

        await makeSwap(signers[0], [WETH, VST], "5.0");
        const tokenBalance = await getBalance(signers[0].address, VST);
        await approve(signers[0], stake.address, VST);
        await stake.addRewardTokens(tokenBalance);
        await stake.setActive();

        for (let i = 0; i < 5; i++) {
            await nft.connect(signers[i]).mint();
            await nft.connect(signers[i]).mint();

            await nft.connect(signers[i]).setApprovalForAll(stake.address, true);
        }

        for (let i = 1; i < 13; i++) {
            let owner = await nft.ownerOf(i);
            ids.push({
                account: owner,
                id: i
            });
        }

    });

    it("Should deposit, withdraw, and claim rewards", async function () {
        // Get tokens owned by signer 0
        let tokens = ids.filter(t => t.account === signers[0].address);

        // Stake 2 NFTs
        await stake.stakeToken(tokens[0].id);
        await stake.stakeToken(tokens[1].id);

        // Increase time by one period (3 months)
        await ethers.provider.send('evm_increaseTime', [2628001 * 3]);
        await ethers.provider.send('evm_mine', []);

        // Get earned rewards and expect them to equal 100 / month / token. 100 * 3 months * 2 tokens staked = 600
        let rewards = await stake.earned(signers[0].address).then((res: BigNumber) => Number(ethers.utils.formatEther(res.toString())));
        expect(rewards).to.equal(600);

        // Withdraw one NFT. This should also claim rewards
        await stake.withdraw(tokens[0].id);

        // Check to ensure earned rewards are now 0
        rewards = await stake.earned(signers[0].address).then((res: BigNumber) => Number(ethers.utils.formatEther(res.toString())));
        expect(rewards).to.equal(0);

        // Increase by one period (3 months)
        await ethers.provider.send('evm_increaseTime', [2628001 * 3]);
        await ethers.provider.send('evm_mine', []);

        // Rewards should be equal to 300 (100 per month per token for 3 months and 1 token staked)
        rewards = await stake.earned(signers[0].address).then((res: BigNumber) => Number(ethers.utils.formatEther(res.toString())));
        expect(rewards).to.equal(300);
    });
});
