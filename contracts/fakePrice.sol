pragma solidity 0.7.4;

contract fakePrice {
    function latestAnswer() external view returns (int256) {
        return 213555000000000;
    }
}
