// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./lib/Context.sol";
import "./lib/SafeMath.sol";
import "./lib/Address.sol";
import "./lib/Ownable.sol";

import "./Token.sol";

contract Raffle is Context, Ownable {
    using SafeMath for uint256;
    using Address for address;
    
    struct DeletableIndex {
        uint256 index;
        bool active;
    }
    
    mapping (address => DeletableIndex) public raffleAddressIndexes;
    address[] public raffleAddresses;
    mapping (address => bool) public excluded;
    
    Token public tokenContract;
    
    // TODO change public to private when needed
    address public trustedParty;
    uint256 public storedBlockNumber;
    bytes32 public sealedSeed;
    bool public raffleInProgress = false;
    bool public sealSet = false;
    
    modifier onlyTokenContract() {
        require(_msgSender() == address(tokenContract), "Only the token contract can call this function");
        _;
    }
    
    event StartRaffle(bytes32 seal, uint256 blockNumber);
    event EndRaffle(address winner, uint256 sum, bytes32 seed);
    event AddRaffleParticipant(address account, uint256 balance);
    event RemoveRaffleParticipant(address account, uint256 balance); 
    
    uint256 public minOverheadWinAmount = 10 ** 2 * 10 ** 6 * 10 ** 9;
    
    uint256 public contractBalanceRatio = 100;
    uint256 public winnerBalanceRatio = 2;
    
    uint256 public minSupplyBalanceRatioToEnter = 100000;
    
    constructor (Token _tokenContract) {
        tokenContract = Token(_tokenContract);
        trustedParty = _msgSender();
        
        excluded[address(this)] = true;
    }
    
    function setMinSupplyBalanceToEnter(uint256 _minSupplyBalanceRatioToEnter) public onlyOwner {
        minSupplyBalanceRatioToEnter = _minSupplyBalanceRatioToEnter;
    }
    
    function setWinnerBalanceRatio(uint256 _winnerBalanceRatio) public onlyOwner {
        winnerBalanceRatio = _winnerBalanceRatio;
    }
    
    function setContractBalanceRatio(uint256 _contractBalanceRatio) public onlyOwner {
        contractBalanceRatio = _contractBalanceRatio;
    }
    
    function setMinOverheadWinAmount(uint256 _minOverheadWinAmount) public onlyOwner {
        minOverheadWinAmount = _minOverheadWinAmount;
    }
    
    function startRaffle(bytes32 _sealedSeed) public onlyOwner {
        if (raffleInProgress && block.number.sub(storedBlockNumber) >= 256) {
            raffleInProgress = false;
            sealSet = false;
            sealedSeed = 0;
        }
        
        require (!raffleInProgress, "Raffle already in progress, finish the first one first");
        require (!sealSet, "A seal is already set");
        require (tokenContract.balanceOf(address(this)) > 0, "Not enough balance in the raffle");
        
        raffleInProgress = true;
        sealSet = true;
        sealedSeed = _sealedSeed;
        storedBlockNumber = block.number + 1;
        
        emit StartRaffle(sealedSeed, storedBlockNumber);
    }
    
    function finishRaffle(bytes32 _seed) public onlyOwner returns (address) {
        require (sealSet, "Seal is not set");
        require (raffleInProgress, "A raffle is not started yet");
        require (storedBlockNumber < block.number, "Cannot finish raffle until the storedBlockNumber is reached");
        require (keccak256(abi.encodePacked(_msgSender(), _seed)) == sealedSeed, "Cannot verify the seed against the sealed seed");
        
        sealSet = false;
        raffleInProgress = false;
        sealedSeed = 0x0;
        
        uint256 random = uint256(keccak256(abi.encodePacked(_seed, blockhash(storedBlockNumber))));
        address winner = raffleAddresses[random % raffleAddresses.length];
        uint256 winnedAmmount = _calculateWinAmmount(winner);
        
        tokenContract.transfer(winner, winnedAmmount);
        
        emit EndRaffle(winner, winnedAmmount, _seed);
        return raffleAddresses[random % raffleAddresses.length];
    }
    
    function _calculateWinAmmount(address winner) private view returns (uint256) {
        uint256 currentBalance = tokenContract.balanceOf(address(this));
        uint256 winnerBalance = tokenContract.balanceOf(winner);
        
        uint256 calculatedTotalBalance = currentBalance.div(contractBalanceRatio);
        uint256 calculatedWinnerBalance = winnerBalance.div(winnerBalanceRatio);
        
        if (calculatedTotalBalance > calculatedWinnerBalance) {
            return calculatedWinnerBalance;
        } else {
            if (calculatedTotalBalance < minOverheadWinAmount) {
                return minOverheadWinAmount > currentBalance ? currentBalance : minOverheadWinAmount;
            } else {
                return calculatedTotalBalance;
            }
        }
    }
    
    function updateBalances(address sender, address recipient, uint256 senderBalance, uint256 recipientBalance, uint256 remainingSupply) public payable onlyTokenContract {
        if(!excluded[sender]) {
            _checkAddToRaffle(sender, senderBalance, remainingSupply);
        }

        if(!excluded[recipient]) {
            _checkAddToRaffle(recipient, recipientBalance, remainingSupply);
        }
    }
    
    
    function _checkEnoughBalance (uint256 balance, uint256 remainingSupply) private view returns (bool) {
      return balance >= remainingSupply.div(minSupplyBalanceRatioToEnter);
    }
    
    function _checkAddToRaffle(address holder, uint256 balance, uint256 remainingSupply) private {
        bool hasBalanceForRaffle = _checkEnoughBalance(balance, remainingSupply);
        
        if (!hasBalanceForRaffle && raffleAddressIndexes[holder].active) {
            DeletableIndex storage deletedIndex = raffleAddressIndexes[holder];
            address lastAddress = raffleAddresses[raffleAddresses.length - 1];
            address deletedAddress = raffleAddresses[deletedIndex.index];
            raffleAddresses[deletedIndex.index] = lastAddress;
            raffleAddresses.pop();
            raffleAddressIndexes[lastAddress] = deletedIndex;
            raffleAddressIndexes[deletedAddress].active = false;
            
            emit RemoveRaffleParticipant(holder, balance);
        } else if (hasBalanceForRaffle && !raffleAddressIndexes[holder].active) {
            raffleAddresses.push(holder);
            raffleAddressIndexes[holder] = DeletableIndex({
                index : raffleAddresses.length - 1,
                active: true
            });
            
            emit AddRaffleParticipant(holder, balance);
        }
    }
    
    function isParticipant(address account) public view returns (bool) {
        return raffleAddressIndexes[account].active;
    }
    
    function excludeAccount(address account) external onlyTokenContract {
        excluded[account] = true;
    }
    
    function includeAccount(address account) external onlyTokenContract {
        excluded[account] = false;
    }
}