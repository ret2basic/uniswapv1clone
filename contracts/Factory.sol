//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Exchange.sol";

contract Factory {
    // This mapping stores the address of every exchange
    // It can be read by getExchange() for lookup
    mapping(address => address) public tokenToExchange;

    function createExchange(address _tokenAddress) public returns (address) {
        require(_tokenAddress != address(0), "invalid token address");
        
        // address type defaults to address(0)
        // If not address(0) then the exchange was already created
        require(
            tokenToExchange[_tokenAddress] == address(0),
            "exchange already exists"
        );

        // `exchange` is a contract object
        Exchange exchange = new Exchange(_tokenAddress);
        // A contract object can be casted to `address()` to get its address
        tokenToExchange[_tokenAddress] = address(exchange);

        return address(exchange);
    }

    function getExchange(address _tokenAddress) public view returns (address) {
        return tokenToExchange[_tokenAddress];
    }

}