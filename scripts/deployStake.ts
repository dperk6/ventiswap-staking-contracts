// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { ethers } from "hardhat";
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

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  const signers = await ethers.getSigners();

  const VST = "0xb7C2fcD6d7922eddd2A7A9B0524074A60D5b472C";

  // We get the contract to deploy
  const Stake = await ethers.getContractFactory("VentiStakeV2");
  const stake = await Stake.connect(signers[5]).deploy(VST);

  await stake.deployed();

  console.log("VentiSwapStakingV2 deployed to:", stake.address);

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

  const inc = list.length / 4;

  const quarters = list.reduce((result: any[], item, index) => {
      const chunkIndex = Math.floor(index / inc);

      if (!result[chunkIndex]) {
          result[chunkIndex] = [];
      }

      result[chunkIndex].push(item);

      return result;
  }, []);

  await stake.connect(signers[5]).stakeOnBehalfOfAll(quarters[0]);
  console.log('Batch 1 completed');

  await stake.connect(signers[5]).stakeOnBehalfOfAll(quarters[1]);
  console.log('Batch 2 completed');

  await stake.connect(signers[5]).stakeOnBehalfOfAll(quarters[2]);
  console.log('Batch 3 completed');

  await stake.connect(signers[5]).stakeOnBehalfOfAll(quarters[3]);
  console.log('Batch 4 completed');

  console.log('State migration is complete');
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
