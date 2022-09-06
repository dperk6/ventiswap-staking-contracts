// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/IVentiheadzStake.sol";
import "./Math.sol";

library NFTStake {

    function stakedTokens(IVentiheadzStake.UserData memory user) internal pure returns (uint256[] memory)
    {
        uint256[] memory tokens = new uint256[](user.totalStaked);

        if (user.totalStaked > 0) {
            tokens[0] = user.id1;
        }
        if (user.totalStaked > 1) {
            tokens[1] = user.id2;
        }
        if (user.totalStaked > 2) {
            tokens[2] = user.id3;
        }
        if (user.totalStaked > 3) {
            tokens[3] = user.id4;
        }
        if (user.totalStaked > 4) {
            tokens[4] = user.id5;
        }

        return tokens;
    }

    function pendingReward(IVentiheadzStake.UserData memory user, uint256 monthlyReward) internal view returns (uint256)
    {
        if (user.totalStaked == 0) {
            return 0;
        }

        uint256 timePassed = block.timestamp - user.timeStaked;
        uint256 periodsPassed = timePassed > 0 ? Math.floorDiv(timePassed, 7884000) : 0;
        uint256 interimTime = timePassed - (periodsPassed * 7884000);
        uint256 pending = user.totalStaked * (monthlyReward * 3) * interimTime / 7884000;

        return pending;
    }

    function earned(IVentiheadzStake.UserData memory user, uint256 paid, uint256 monthlyReward, uint256 end) internal pure returns (uint256)
    {
        if (user.totalStaked == 0) return 0;
        
        uint256 periodsPassed = Math.floorDiv(end - user.timeStaked, 7884000);

        if (periodsPassed == 0) return 0;

        uint256 totalReward = user.totalStaked * (monthlyReward * 3) * periodsPassed - paid;

        return totalReward;
    }

    function withdrawId(IVentiheadzStake.UserData storage user, uint16 tokenId) internal returns (bool)
    {
        uint256 id;
        uint256 x;

        if (tokenId == user.id1) {
            id = user.id1;
            x = 1;
            user.id1 = 0;
        }
        else if (tokenId == user.id2) {
            id = user.id2;
            x = 2;
            user.id2 = 0;
        }
        else if (tokenId == user.id3) {
            id = user.id3;
            x = 3;
            user.id3 = 0;
        }
        else if (tokenId == user.id4) {
            id = user.id4;
            x = 4;
            user.id4 = 0;
        }
        else if (tokenId == user.id5) {
            id = user.id5;
            x = 5;
            user.id5 = 0;
        }

        require(id != 0, "Token ID not staked by user");

        uint256 total = user.totalStaked;
        user.totalStaked -= 1;

        if (total == 2) {
            if (x == 1) {
                user.id1 = user.id2;
            }
        }
        if (total == 3) {
            if (x == 1) {
                user.id1 = user.id2;
                user.id2 = user.id3;
                user.id3 = 0;
            } else if (x == 2) {
                user.id2 = user.id3;
                user.id3 = 0;
            }
        }
        if (total == 4) {
            if (x == 1) {
                user.id1 = user.id2;
                user.id2 = user.id3;
                user.id3 = user.id4;
                user.id4 = 0;
            } else if (x == 2) {
                user.id2 = user.id3;
                user.id3 = user.id4;
                user.id4 = 0;
            } else if (x == 3) {
                user.id3 = user.id4;
                user.id4 = 0;
            }
        }
        if (total == 5) {
            if (x == 1) {
                user.id1 = user.id2;
                user.id2 = user.id3;
                user.id3 = user.id4;
                user.id4 = user.id5;
                user.id5 = 0;
            } else if (x == 2) {
                user.id2 = user.id3;
                user.id3 = user.id4;
                user.id4 = user.id5;
                user.id5 = 0;
            } else if (x == 3) {
                user.id3 = user.id4;
                user.id4 = user.id5;
                user.id5 = 0;
            } else if (x == 4) {
                user.id4 = user.id5;
                user.id5 = 0;
            }
        }

        return true;
    }
}