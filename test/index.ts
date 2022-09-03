import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumber } from "ethers";
import { ethers, network } from "hardhat";
import { TestToken, VentiStakeV2 } from "../typechain";
import { parse } from "csv-parse";
import fs from "fs";
import path from "path";

interface IStaker {
  account: string;
  lock: string;
  timestamp: string;
  staked: string;
  paid: string;
}

describe("Ventiswap Staking", function () {
  let token: TestToken;
  let signers: SignerWithAddress[];
  let ventiStake: VentiStakeV2;

  this.beforeEach(async () => {
    signers = await ethers.getSigners();

    const VentiStake = await ethers.getContractFactory("VentiStakeV2");
    const Token = await ethers.getContractFactory("TestToken");
    token = await Token.deploy(ethers.utils.parseEther('21000000'));
    await token.deployed();
    ventiStake = await VentiStake.deploy(token.address);
    await ventiStake.deployed();

    await token.connect(signers[0]).transfer(signers[1].address, ethers.utils.parseEther('5000'));
    await token.connect(signers[0]).transfer(signers[2].address, ethers.utils.parseEther('5000'));
    await token.connect(signers[0]).transfer(signers[3].address, ethers.utils.parseEther('5000'));
    await token.connect(signers[0]).transfer(signers[4].address, ethers.utils.parseEther('5000'));

    for (let i = 1; i < 5; i++) {
      await token.connect(signers[i]).approve(ventiStake.address, ethers.constants.MaxUint256);
    }

    await token.connect(signers[0]).approve(ventiStake.address, ethers.utils.parseEther('10000'));
    await ventiStake.connect(signers[0]).fundStaking(ethers.utils.parseEther('10000'));
    await ventiStake.connect(signers[0]).enableStaking();
  });

  it("Should be marked active and hold reward tokens", async () => {
    // Confirm staking is active
    expect(await ventiStake.isActive()).to.equal(true);

    // Check if balance is equal to rewards (i.e. no one has staked)
    let ventiStakeBalance = await token.balanceOf(ventiStake.address).then((res: BigNumber) => Number(ethers.utils.formatEther(res.toString())));
    let ventiStakeRewards = await ventiStake.totalRewards().then((res: BigNumber) => Number(ethers.utils.formatEther(res.toString())));
    expect(ventiStakeBalance).to.equal(ventiStakeRewards);
  });

  it("Should allow staking, claiming, and withdraws", async () => {
    // Lock 1000 tokens for 6 months (3% per month)
    await ventiStake.connect(signers[1]).deposit(ethers.utils.parseEther('1000'), 3);
    let s1Staked: number | string = await ventiStake.balanceOf(signers[1].address).then((res: BigNumber) => Number(ethers.utils.formatEther(res.toString())));
    let totalSupply = await ventiStake.totalSupply().then((res: BigNumber) => Number(ethers.utils.formatEther(res.toString())));
    expect(s1Staked).to.equal(1000);
    expect(totalSupply).to.equal(1000);

    // Increase time by 1 month
    await ethers.provider.send('evm_increaseTime', [2628001]);
    await ethers.provider.send('evm_mine', []);

    // Check if one month's rewards = 1000 * .03
    let rewards = await ventiStake.earned(signers[1].address).then((res: BigNumber) => Number(ethers.utils.formatEther(res.toString())));
    expect(rewards).to.equal(1000 * 0.03);
    

    await ventiStake.connect(signers[1]).claimRewards();

    // Increase time by 1 month
    await ethers.provider.send('evm_increaseTime', [2628001]);
    await ethers.provider.send('evm_mine', []);

    // Check if received another month's rewards
    rewards = await ventiStake.earned(signers[1].address).then((res: BigNumber) => Number(ethers.utils.formatEther(res.toString())));
    expect(rewards).to.equal(1000 * 0.03);

    await ventiStake.connect(signers[1]).claimRewards();

    // Increase time by 4 months - rest of lock period
    await ethers.provider.send('evm_increaseTime', [2628001 * 4]);
    await ethers.provider.send('evm_mine', []);
  
    // Check if received 4 months' rewards
    rewards = await ventiStake.earned(signers[1].address).then((res: BigNumber) => Number(ethers.utils.formatEther(res.toString())));
    expect(rewards).to.equal(1000 * 0.03 * 4);

    // Check if user can withdraw their full stake. This will also claim oustanding rewards
    await ventiStake.connect(signers[1]).withdraw(ethers.utils.parseEther('1000'));
    s1Staked = await ventiStake.balanceOf(signers[1].address).then((res: BigNumber) => Number(ethers.utils.formatEther(res.toString())));
    expect(s1Staked).to.equal(0);
  });

  it("Should allow multiple stakes and withdrawals", async () => {

    // For signer 1, lock 1000 tokens for 6 months
    await ventiStake.connect(signers[1]).deposit(ethers.utils.parseEther('1000'), 3);
    let s1Staked = await ventiStake.balanceOf(signers[1].address).then((res: BigNumber) => Number(ethers.utils.formatEther(res.toString())));
    expect(s1Staked).to.equal(1000);

    // For signer 2, lock 2000 tokens for 6 months
    await ventiStake.connect(signers[2]).deposit(ethers.utils.parseEther('2000'), 3);
    let s2Staked = await ventiStake.balanceOf(signers[2].address).then((res: BigNumber) => Number(ethers.utils.formatEther(res.toString())));
    expect(s2Staked).to.equal(2000);

    // For signer 3, lock 3000 tokens for 3 months
    await ventiStake.connect(signers[3]).deposit(ethers.utils.parseEther('3000'), 2);
    let s3Staked = await ventiStake.balanceOf(signers[3].address).then((res: BigNumber) => Number(ethers.utils.formatEther(res.toString())));
    expect(s3Staked).to.equal(3000);

    // For signer 4, lock 4000 tokens for 1 month
    await ventiStake.connect(signers[4]).deposit(ethers.utils.parseEther('4000'), 1);
    let s4Staked = await ventiStake.balanceOf(signers[4].address).then((res: BigNumber) => Number(ethers.utils.formatEther(res.toString())));
    expect(s4Staked).to.equal(4000);

    // Increase time by 1 month
    await ethers.provider.send('evm_increaseTime', [2628001]);
    await ethers.provider.send('evm_mine', []);

    // Check signer 1 rewards are equal to 3% of 1000
    let s1Rewards = await ventiStake.earned(signers[1].address).then((res: BigNumber) => Number(ethers.utils.formatEther(res.toString())));
    expect(s1Rewards).to.equal(1000 * .03);

    // Check signer 2 rewards are equal to 3% of 2000
    let s2Rewards = await ventiStake.earned(signers[2].address).then((res: BigNumber) => Number(ethers.utils.formatEther(res.toString())));
    expect(s2Rewards).to.equal(2000 * .03);

    // Check signer 3 rewards are equal to 2% of 3000
    let s3Rewards = await ventiStake.earned(signers[3].address).then((res: BigNumber) => Number(ethers.utils.formatEther(res.toString())));
    expect(s3Rewards).to.equal(3000 * .02);

    // Check signer 4 rewards are equal to 1% of 4000
    let s4Rewards = await ventiStake.earned(signers[4].address).then((res: BigNumber) => Number(ethers.utils.formatEther(res.toString())));
    expect(s4Rewards).to.equal(4000 * .01);

    // Claims 1 month of rewards from signer 1
    await ventiStake.connect(signers[1]).claimRewards();
    let s1Claimed = 1000 * .03; // We know this to be correct due to check above

    // Check that signer 1 has 0 outstanding rewards
    expect(await ventiStake.earned(signers[1].address)).to.equal(0);

    // Deposits an additional 1000 for signer 2
    let s2Pending = await ventiStake.pendingReward(signers[2].address).then((res: BigNumber) => Number(ethers.utils.formatEther(res.toString())));
    await ventiStake.connect(signers[2]).deposit(ethers.utils.parseEther('1000'), 3);
    s2Pending += await ventiStake.pendingReward(signers[2].address).then((res: BigNumber) => Number(ethers.utils.formatEther(res.toString())));
    s2Staked = await ventiStake.balanceOf(signers[2].address).then((res: BigNumber) => Number(ethers.utils.formatEther(res.toString())));
    s2Rewards = await ventiStake.earned(signers[2].address).then((res: BigNumber) => Number(ethers.utils.formatEther(res.toString())));

    // Check is signer 2 rewards amount is now 0 and staked amount is equal to 2000 initial, 1000 additional, and rewards
    expect(s2Rewards).to.equal(0);
    // Need to add small difference to cover for additional pending rewards
    expect(s2Staked).to.greaterThanOrEqual(3000 + s2Pending + (2000 * .03));
    expect(s2Staked).to.lessThanOrEqual(3000 + s2Pending + 1 + (2000 * .03));

    // Increase time by 1 month
    await ethers.provider.send('evm_increaseTime', [2628001]);
    await ethers.provider.send('evm_mine', []);

    // Check if signer 2's rewards are equal to 3% of the staked amount for 1 month, since 1 has already been claimed
    s2Rewards = await ventiStake.earned(signers[2].address).then((res: BigNumber) => Number(ethers.utils.formatEther(res.toString())));
    expect(s2Rewards).to.equal(s2Staked * .03);

    // Check if signer 4's rewards are equal to 1% of staked amount * 2 months
    s4Rewards = await ventiStake.earned(signers[4].address).then((res: BigNumber) => Number(ethers.utils.formatEther(res.toString())));
    expect(s4Rewards).to.equal(4000 * .01 * 2);

    // Withdraw signer 4's stake and check to ensure it is 0
    await ventiStake.connect(signers[4]).withdraw(ethers.utils.parseEther('4000'));
    s4Staked = await ventiStake.balanceOf(signers[4].address).then((res: BigNumber) => Number(ethers.utils.formatEther(res.toString())));
    expect(s4Staked).to.equal(0);

    // Increase time by 4 months (6 total)
    await ethers.provider.send('evm_increaseTime', [2628001 * 4]);
    await ethers.provider.send('evm_mine', []);

    // Signer 1 - 1000 locked for 6 months, staked for 6 months (should receive rewards for 5 months since first month was claimed)
    s1Rewards = await ventiStake.earned(signers[1].address).then((res: BigNumber) => Number(ethers.utils.formatEther(res.toString())));
    expect(s1Rewards).to.equal(1000 * 0.03 * 5);
    await ventiStake.connect(signers[1]).withdraw(ethers.utils.parseEther('1000'));

    // Signer 2 - Inital stake of 2000 with 6 month lock, then restake another 1000 + rewards
    // Rewards were claimed on redeposit, so there should be 5 months of rewards
    s2Rewards = await ventiStake.earned(signers[2].address).then((res: BigNumber) => Number(ethers.utils.formatEther(res.toString())));
    expect(s2Rewards).to.equal(s2Staked * .03 * 5);

    // Signer 2's stake should still be locked as 6 months has not passed since last deposit
    expect(await ventiStake.withdrawable(signers[2].address)).to.equal(false);

    // Signer 3 - 3000 locked for 3 months, staked for 6 months
    s3Rewards = await ventiStake.earned(signers[3].address).then((res: BigNumber) => Number(ethers.utils.formatEther(res.toString())));
    expect(s3Rewards).to.equal(3000 * 0.02 * 6);
    await ventiStake.connect(signers[3]).withdraw(ethers.utils.parseEther('3000'));

    // Increase time by a month
    await ethers.provider.send('evm_increaseTime', [2628001]);
    await ethers.provider.send('evm_mine', []);

    // Withdraw signer 2's stake
    let staked = await ventiStake.balanceOf(signers[2].address).then((res: BigNumber) => res.toString());
    await ventiStake.connect(signers[2]).withdraw(staked);
    expect(await ventiStake.balanceOf(signers[2].address)).to.equal(0);

    // Expect total supply to be 0
    expect(await ventiStake.totalSupply()).to.equal(0);

  });

  it("Should upload state history to contract", async () => {
    const VST = "0xb7C2fcD6d7922eddd2A7A9B0524074A60D5b472C";
    const ADDR = "0x7FBF79Ebd2E57EdC8673edbcb41662676ba9eD5a";

    await network.provider.send("hardhat_impersonateAccount", [ADDR]);

    const signer = await ethers.getSigner(ADDR);

    await network.provider.send("hardhat_setBalance", [
      ADDR,
      "0x3130303030303030303030303030303030303030",
    ]);

    const existing = await ethers.getContractAt("IVentiSwapStakingV2", "0x281A39d6db514F159E87FD17275E981d42292b2a", signer);
    const VentiStake = await ethers.getContractFactory("VentiStakeV2");
    const newStake = await VentiStake.connect(signer).deploy(VST);
    await newStake.deployed();

    const process = async (): Promise<IStaker[]> => {
      const addresses: IStaker[] = [];
      const parseAddresses = fs
        .createReadStream(path.join(__dirname, "..", "scripts", "new.csv"))
        .pipe(parse());

      const parseExtra = fs
        .createReadStream(
          path.join(__dirname, "..", "scripts", "multiple_deposits.csv")
        )
        .pipe(parse());

      let list = [];

      for await (let item of parseExtra) {
        list.push({
          account: item[0],
          extra: item[1],
        });
      }

      for await (let item of parseAddresses) {
        const find = list.find((l) => l.account === item[0]);
        addresses.push({
          account: item[0],
          staked: find
            ? ethers.BigNumber.from(find.extra).add(item[1]).toString()
            : item[1],
          timestamp: item[2],
          lock: item[3],
          paid: item[4],
        });
      }

      return addresses;
    };

    const list = await process();

    await existing.connect(signer).closeRewards();
    let rewardsBalance = await existing.totalRewards().then((res: BigNumber) => res.toString());
    await existing.connect(signer).withdrawRewardTokens();

    expect(await existing.totalRewards()).to.equal(0);
    expect(await existing.isActive()).to.equal(false);

    let vst = await ethers.getContractAt("ERC20", VST, signer);
    let balance = await vst.balanceOf(existing.address);
    
    await existing.connect(signer).stakeOnBehalfOf(ADDR, balance.toString(), 0, 1);
    await existing.connect(signer).emergencyWithdrawal();

    expect(await vst.balanceOf(existing.address)).to.equal(0);

    const inc = list.length / 4;

    const quarters = list.reduce((result: any[], item, index) => {
        const chunkIndex = Math.floor(index / inc);

        if (!result[chunkIndex]) {
            result[chunkIndex] = [];
        }

        result[chunkIndex].push(item);

        return result;
    }, []);

    await newStake.connect(signer).stakeOnBehalfOfAll(quarters[0]);
    await newStake.connect(signer).stakeOnBehalfOfAll(quarters[1]);
    await newStake.connect(signer).stakeOnBehalfOfAll(quarters[2]);
    await newStake.connect(signer).stakeOnBehalfOfAll(quarters[3]);

    let totalSupply = await newStake.totalSupply();

    await vst.connect(signer).transfer(newStake.address, totalSupply.toString());
    await vst.connect(signer).approve(newStake.address, ethers.constants.MaxUint256);
    await newStake.connect(signer).fundStaking(rewardsBalance);

    await newStake.connect(signer).enableStaking();
  });
});
