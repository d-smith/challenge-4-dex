// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/**
 * @title DEX Template
 * @author stevepham.eth and m00npapi.eth
 * @notice Empty DEX.sol that just outlines what features could be part of the challenge (up to you!)
 * @dev We want to create an automatic market where our contract will hold reserves of both ETH and 🎈 Balloons. These reserves will provide liquidity that allows anyone to swap between the assets.
 * NOTE: functions outlined here are what work with the front end of this branch/repo. Also return variable names that may need to be specified exactly may be referenced (if you are confused, see solutions folder in this repo and/or cross reference with front-end code).
 */
contract DEX {
    /* ========== GLOBAL VARIABLES ========== */

    using SafeMath for uint256; //outlines use of SafeMath for uint256 variables
    IERC20 token; //instantiates the imported contract

    uint256 public totalLiquidity;
    mapping(address => uint256) public liquidity;

    /* ========== EVENTS ========== */

    /**
     * @notice Emitted when ethToToken() swap transacted
     */
    event EthToTokenSwap(address sender, string message, uint256 eth, uint256 tokens);

    /**
     * @notice Emitted when tokenToEth() swap transacted
     */
    event TokenToEthSwap(address sender, string message, uint256 eth, uint256 tokens);

    /**
     * @notice Emitted when liquidity provided to DEX and mints LPTs.
     */
    event LiquidityProvided(address sender, uint liquidityMinted, uint256 eth, uint256 tokens);

    /**
     * @notice Emitted when liquidity removed from DEX and decreases LPT count within DEX.
     */
    event LiquidityRemoved(address sender, uint amount, uint256 eth, uint256 tokens);

    /* ========== CONSTRUCTOR ========== */

    constructor(address token_addr)  {
        token = IERC20(token_addr); //specifies the token address that will hook into the interface and be used through the variable 'token'
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @notice initializes amount of tokens that will be transferred to the DEX itself from the erc20 contract mintee (and only them based on how Balloons.sol is written). Loads contract up with both ETH and Balloons.
     * @param tokens amount to be transferred to DEX
     * @return totalLiquidity is the number of LPTs minting as a result of deposits made to DEX contract
     * NOTE: since ratio is 1:1, this is fine to initialize the totalLiquidity (wrt to balloons) as equal to eth balance of contract.
     */
    function init(uint256 tokens) public payable returns (uint256) {
        require(totalLiquidity == 0, "Contract has already been initialized");
        totalLiquidity = address(this).balance;
        liquidity[msg.sender] = totalLiquidity;
        bool transferred = token.transferFrom(msg.sender, address(this),tokens);
        require(transferred, "Error initializing dex contract");
        return totalLiquidity;
    }

    /**
     * @notice returns yOutput, or yDelta for xInput (or xDelta)
     * @dev Follow along with the [original tutorial](https://medium.com/@austin_48503/%EF%B8%8F-minimum-viable-exchange-d84f30bd0c90) Price section for an understanding of the DEX's pricing model and for a price function to add to your contract. You may need to update the Solidity syntax (e.g. use + instead of .add, * instead of .mul, etc). Deploy when you are done.
     */
    function price (
        uint256 xInput,
        uint256 xReserves,
        uint256 yReserves
    ) public pure returns (uint256 yOutput) {
        uint256 xInputWithFee = xInput.mul(997);
        uint256 numerator = xInputWithFee.mul(yReserves);
        uint256 denominator = (xReserves.mul(1000)).add(xInputWithFee);
        return (numerator / denominator);
    }

    /**
     * @notice returns liquidity for a user. Note this is not needed typically due to the `liquidity()` mapping variable being public and having a getter as a result. This is left though as it is used within the front end code (App.jsx).
     * if you are using a mapping liquidity, then you can use `return liquidity[lp]` to get the liquidity for a user.
     *
     */
    function getLiquidity(address lp) public view returns (uint256 liq) {
        liq = liquidity[lp];
    }

    /**
     * @notice sends Ether to DEX in exchange for $BAL
     */
    function ethToToken() public payable returns (uint256 tokenOutput) {
        require(msg.value > 0, "Cannot call with zero ETH value");

        uint256 ethReserve = address(this).balance.sub(msg.value);
        uint256 tokenReserve = token.balanceOf(address(this));
        tokenOutput = price(msg.value,ethReserve,tokenReserve);

        emit EthToTokenSwap(msg.sender,"Eth to balloons", msg.value, tokenOutput);
        bool xferStatus = token.transfer(msg.sender, tokenOutput);
        require(xferStatus, "error transferring tokens");
    }

    /**
     * @notice sends $BAL tokens to DEX in exchange for Ether
     */
    function tokenToEth(uint256 tokenInput) public returns (uint256 ethOutput) {
        // Checks
        require(tokenInput > 0, "Must specify number of tokens greater than zero");

        // Effects
        uint256 tokenReserve = token.balanceOf(address(this));
        uint256 ethReserve = address(this).balance;

        ethOutput = price(tokenInput,tokenReserve,ethReserve);

        emit TokenToEthSwap(msg.sender, "Balloons to Eth", ethOutput, tokenInput);

        // Interactions
        require(token.transferFrom(msg.sender,address(this),tokenInput), "Error transferring token to smart contract");
        (bool sent,) = msg.sender.call{value: ethOutput}("");
        require(sent, "Error sending ETH to caller");

    }

    /**
     * @notice allows deposits of $BAL and $ETH to liquidity pool
     * NOTE: parameter is the msg.value sent with this function call. That amount is used to determine the amount of $BAL needed as well and taken from the depositor.
     * NOTE: user has to make sure to give DEX approval to spend their tokens on their behalf by calling approve function prior to this function call.
     * NOTE: Equal parts of both assets will be removed from the user's wallet with respect to the price outlined by the AMM.
     */
    function deposit() public payable returns (uint256 tokensDeposited) {
        // Checks
        require(msg.value > 0, "Must send eth to deposit");

        // Effects

        // Determine reserves prior to deposit
        uint256 ethReserves = address(this).balance.sub(msg.value);
        uint256 tokenReserves = token.balanceOf(address(this));


        // Figure out the amount of tokens that must be deposited based 
        // to maintain the current reserves ration, e.g.
        // tokens dep / eth dep = tokens reserve / eth reserve

        // Note - see https://t.me/c/1655715571/106 for the add of 1
        tokensDeposited = (msg.value.mul(tokenReserves) / ethReserves).add(1);


        // Now calculate the changes to liquidity based on the deposit and the current
        // eth reserves
        uint256 liquidityMinted = msg.value.mul(totalLiquidity) / ethReserves;
        liquidity[msg.sender] = liquidity[msg.sender].add(liquidityMinted);
        totalLiquidity = totalLiquidity.add(liquidityMinted);

        emit LiquidityProvided(msg.sender, liquidityMinted, msg.value, tokensDeposited);

        // Interactions
        require(token.transferFrom(msg.sender, address(this), tokensDeposited),
            "Error transferring tokens from depositor");

    }

    /**
     * @notice allows withdrawal of $BAL and $ETH from liquidity pool
     * NOTE: with this current code, the msg caller could end up getting very little back if the liquidity is super low in the pool. I guess they could see that with the UI.
     */
    function withdraw(uint256 amount) public returns (uint256 eth_amount, uint256 token_amount) {
        // Checks

        // Does the liquidity contribution of the withdrawer allow the requested 
        // withdrawal amount?
        require(amount> 0, "Request amount must be greater than 0");
        require(liquidity[msg.sender] > amount, "Request amount greater than liquidity contribution indidates");

        // Effects

        // Determine amount of eth to withdraw
        uint256 ethReserves = address(this).balance;
        eth_amount = amount.mul(ethReserves) / totalLiquidity;

        // Determine tokens to withdraw
        uint256 tokenReserves = token.balanceOf(address(this));
        token_amount = amount.mul(tokenReserves) / totalLiquidity;

        // Update totalLiquidity and the liquidity of the sender
        totalLiquidity = totalLiquidity.sub(amount);
        liquidity[msg.sender] = liquidity[msg.sender].sub(amount);

        // Create event to emit
        emit LiquidityRemoved(msg.sender, amount, eth_amount, token_amount);

        // Interactions
        (bool sent, ) = payable(msg.sender).call{ value: eth_amount }("");
        require(sent, "Error sending eth");
        require(token.transfer(msg.sender, token_amount),
            "Error transferring tokens");
    }
}
