//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IExchange {
    function ethToTokenSwap(uint256 _minTokens) external payable;
    function ethToTokenTransfer(uint256 _minTokens, address _recipient) external payable;
}

interface IFactory {
    function getExchange(address _tokenAddress) external returns (address);
}

contract Exchange is ERC20 {
    address public tokenAddress;
    address public factoryAddress;

    constructor(address _token) ERC20("uniswapv1clone", "uniswapv1") {
        require(_token != address(0), "invalid token address");

        tokenAddress = _token;
        factoryAddress = msg.sender;
    }

    function addLiquidity(uint256 _tokenAmount) public payable returns(uint256) {
        // At initialization of an exchange
        // Any token/eth ratio is allowed
        if (getReserve() == 0) {
            IERC20 token = IERC20(tokenAddress);

            // Collect fund from user and fill that into the pool
            token.transferFrom(msg.sender, address(this), _tokenAmount);

            // Mint LP tokens for the user
            uint256 liquidity = address(this).balance;
            _mint(msg.sender, liquidity);

            return liquidity;
        }
        // Otherwise
        // token/eth ratio must remain the same
        else {
            uint256 ethReserve = address(this).balance - msg.value;
            uint256 tokenReserve = getReserve();
            uint256 tokenAmount = (msg.value * tokenReserve) / ethReserve;
            require(_tokenAmount >= tokenAmount, "insufficient token amount");

            IERC20 token = IERC20(tokenAddress);
            // Not all tokens are deposited
            // `tokenAmount` keeps the token/eth ratio preserved
            token.transferFrom(msg.sender, address(this), tokenAmount);

            // Mint LP tokens to the user
            uint256 liquidity = (totalSupply() * msg.value) / ethReserve;
            _mint(msg.sender, liquidity);

            return liquidity;
        }
    }

    function removeLiquidity(uint256 _amount) public returns (uint256, uint256) {
        require(_amount > 0, "invalid amount");

        // totalSupply() is the total amount of LP tokens
        uint256 ethAmount = (address(this).balance * _amount) / totalSupply();
        uint256 tokenAmount = (getReserve() * _amount) / totalSupply();

        // Burn LP tokens
        _burn(msg.sender, _amount);
        // Transfer both ETH and tokens back to the user
        payable(msg.sender).transfer(ethAmount);
        IERC20(tokenAddress).transfer(msg.sender, tokenAmount);

        return (ethAmount, tokenAmount);
    }

    function getReserve() public view returns (uint256) {
        return IERC20(tokenAddress).balanceOf(address(this));
    }

    function getTokenAmount(uint256 _ethSold) public view returns (uint256) {
        require(_ethSold > 0, "ethSold is too small");

        uint256 tokenReserve = getReserve();

        // inputReserve: ETH
        // outputReserve: ERC20 token
        return getAmount(_ethSold, address(this).balance, tokenReserve);
    }

    function getEthAmount(uint256 _tokenSold) public view returns (uint256) {
        require(_tokenSold > 0, "tokenSold is too small");

        uint256 tokenReserve = getReserve();

        // inputReserve: ETH
        // outputReserve: ERC20 token
        return getAmount(_tokenSold, tokenReserve, address(this).balance);
    }

    function ethToToken(uint256 _minTokens, address recipient) private {
        uint256 tokenReserve = getReserve();
        // address(this).balance - msg.value is the balance before
        // msg.value is sent to this contract
        uint256 tokensBought = getAmount(
            msg.value,
            address(this).balance - msg.value,
            tokenReserve
        );

        // _minTokens is user's bottom line for this swap
        // User is not going to accept anything lower than this amount
        require(tokensBought >= _minTokens, "insufficient output amount");

        IERC20(tokenAddress).transfer(recipient, tokensBought);
    }

    // Swap eth for token and transfer tokens to arbitrary recipient
    function ethToTokenTransfer(uint256 _minTokens, address _recipient) public payable
    {
        ethToToken(_minTokens, _recipient);
    }

    // Swap eth for token and transfer tokens to msg.sender
    function ethToTokenSwap(uint256 _minTokens) public payable {
        ethToToken(_minTokens, msg.sender);
    }

    // Swap: token -> eth
    function tokenToEthSwap(uint256 _tokensSold, uint256 _minEth) public {
        uint256 tokenReserve = getReserve();
        uint256 ethBought = getAmount(_tokensSold, tokenReserve, address(this).balance);

        // _minEth is user's bottom line for this swap
        // User is not going to accept anything below this amount
        require(ethBought >= _minEth, "insufficient output amount");

        // Collect tokens from the user
        IERC20(tokenAddress).transferFrom(
            msg.sender,
            address(this),
            _tokensSold
        );
        // Pay eth to the user
        payable(msg.sender).transfer(ethBought);
    }

    // Swap: input_token -> eth -> output token
    function tokenToTokenSwap(
        uint256 _tokensSold,
        uint256 _minTokensBought,
        address _tokenAddress
    ) public {
        address exchangeAddress = IFactory(factoryAddress).getExchange(
            _tokenAddress
        );
        require(
            exchangeAddress != address(this) && exchangeAddress != address(0),
            "invalid exchange address"
        );

        uint256 tokenReserve = getReserve();
        uint256 ethBought = getAmount(
            _tokensSold,
            tokenReserve,
            address(this).balance
        );

        // Collect input token from the user
        IERC20(tokenAddress).transferFrom(
            msg.sender,
            address(this),
            _tokensSold
        );

        // User transfers msg.value to that exchange and swaps for output token
        // The output token will be sent directly to msg.sender, which is the user
        IExchange(exchangeAddress).ethToTokenTransfer{value: ethBought}(
            _minTokensBought,
            msg.sender
        );
    }

    function getAmount(
        uint256 inputAmount,
        uint256 inputReserve,
        uint256 outputReserve
    ) private pure returns (uint256) {
        require(inputReserve > 0 && outputReserve > 0, "invalid reserves");

        uint256 inputAmountWithFee = inputAmount * 99;
        uint256 numerator = inputAmountWithFee * outputReserve;
        uint256 denominator = (inputReserve * 100) + inputAmountWithFee;

        return numerator / denominator;
    }
}