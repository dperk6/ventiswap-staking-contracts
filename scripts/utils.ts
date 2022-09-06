import { ethers } from "hardhat";
import { BigNumberish, Signer } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

const UNISWAP_ABI = [
    "function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline) external payable returns (uint[] memory amounts)"
  ];  

const TOKEN_ABI = [
    "function approve(address spender, uint256 spender) external returns (bool)",
    "function balanceOf(address account) external view returns (uint256)"
]

const uniswap = new ethers.Contract(
    "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D",
    UNISWAP_ABI,
    ethers.provider
);

export const makeSwap = async (signer: Signer, path: string[], value: string): Promise<void> => {
    await uniswap.connect(signer)
        .swapExactETHForTokens(
            0, path, await signer.getAddress(), 9999999999
        , { value: ethers.utils.parseEther(value)});    
}

export const getBalance = async (account: string, token: string): Promise<BigNumberish> => {
    const contract = new ethers.Contract(token, TOKEN_ABI, ethers.provider);

    return await contract.balanceOf(account);
}

export const approve = async (owner: Signer, spender: string, token: string): Promise<void> => {
    const contract = new ethers.Contract(token, TOKEN_ABI, ethers.provider);
    
    await contract.connect(owner).approve(spender, ethers.constants.MaxUint256);
}

