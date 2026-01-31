// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IEventManager} from "../interfaces/IEventManager.sol";
import {MicroEventLib} from "../libraries/MicroEventLib.sol";
import {IAuraVerifier} from "../interfaces/IAuraVerifier.sol";

/// @title EventManager - Micro-event lifecycle for rapid betting windows
/// @notice Events keyed by bytes32 eventId -> each event's storage is isolated.
///         Creating different events is fully parallel on Monad.
/// @dev LIFECYCLE: NONEXISTENT -> OPEN -> LOCKED -> SETTLED | VOIDED
contract EventManager is IEventManager {
    using MicroEventLib for *;

    // ===================== STORAGE =====================

    struct MicroEvent {
        uint40 openTime;
        uint40 closeTime;
        uint40 settleTime;
        MicroEventLib.EventStatus status;
        uint8 numOutcomes;
        address creator;
        bytes32 priceFeedId;
        uint8 winningOutcome;
        bytes32 auraAttestation;
    }

    mapping(bytes32 => MicroEvent) private _events;
    mapping(address => uint256) public keeperNonces;
    mapping(address => bool) public authorizedKeepers;

    IAuraVerifier public auraVerifier;
    address public settlementProcessor;
    address public owner;

    // ===================== MODIFIERS =====================

    modifier onlyKeeper() {
        require(authorizedKeepers[msg.sender], "EventManager: not keeper");
        _;
    }

    modifier onlySettlement() {
        require(msg.sender == settlementProcessor, "EventManager: not settlement");
        _;
    }

    // ===================== CONSTRUCTOR =====================

    constructor(address _auraVerifier) {
        owner = msg.sender;
        auraVerifier = IAuraVerifier(_auraVerifier);
    }

    // ===================== KEEPER FUNCTIONS =====================

    /// @notice Create a new micro-event with 5-30 second betting window
    function createEvent(
        bytes32 priceFeedId,
        uint40 openTime,
        uint40 closeTime,
        uint8 numOutcomes,
        bytes32 auraAttestation
    ) external onlyKeeper returns (bytes32 eventId) {
        MicroEventLib.validateWindow(openTime, closeTime);
        require(numOutcomes >= 2 && numOutcomes <= 10, "EventManager: invalid outcomes");
        require(openTime >= uint40(block.timestamp), "EventManager: open in past");

        uint256 nonce = keeperNonces[msg.sender]++;
        eventId = MicroEventLib.generateEventId(priceFeedId, openTime, closeTime, nonce);

        require(
            _events[eventId].status == MicroEventLib.EventStatus.NONEXISTENT,
            "EventManager: event exists"
        );

        MicroEvent storage evt = _events[eventId];
        evt.openTime = openTime;
        evt.closeTime = closeTime;
        evt.status = MicroEventLib.EventStatus.OPEN;
        evt.numOutcomes = numOutcomes;
        evt.creator = msg.sender;
        evt.priceFeedId = priceFeedId;
        evt.auraAttestation = auraAttestation;

        emit EventCreated(eventId, openTime, closeTime, priceFeedId);
    }

    /// @notice Lock event when betting window closes (permissionless)
    function lockEvent(bytes32 eventId) external {
        MicroEvent storage evt = _events[eventId];
        require(evt.status == MicroEventLib.EventStatus.OPEN, "EventManager: not open");
        require(block.timestamp >= evt.closeTime, "EventManager: window still open");

        evt.status = MicroEventLib.EventStatus.LOCKED;
        emit EventLocked(eventId);
    }

    // ===================== SETTLEMENT FUNCTIONS =====================

    function settleEvent(bytes32 eventId, uint8 winningOutcome) external onlySettlement {
        MicroEvent storage evt = _events[eventId];
        require(evt.status == MicroEventLib.EventStatus.LOCKED, "EventManager: not locked");
        require(winningOutcome < evt.numOutcomes, "EventManager: invalid outcome");

        evt.status = MicroEventLib.EventStatus.SETTLED;
        evt.winningOutcome = winningOutcome;
        evt.settleTime = uint40(block.timestamp);

        emit EventSettled(eventId, winningOutcome);
    }

    function voidEvent(bytes32 eventId) external onlySettlement {
        MicroEvent storage evt = _events[eventId];
        require(
            evt.status == MicroEventLib.EventStatus.OPEN || evt.status == MicroEventLib.EventStatus.LOCKED,
            "EventManager: cannot void"
        );

        evt.status = MicroEventLib.EventStatus.VOIDED;
        emit EventVoided(eventId);
    }

    // ===================== VIEW FUNCTIONS =====================

    function getEvent(bytes32 eventId)
        external
        view
        returns (
            uint40 openTime,
            uint40 closeTime,
            uint40 settleTime,
            MicroEventLib.EventStatus status,
            uint8 numOutcomes,
            address creator,
            bytes32 priceFeedId,
            uint8 winningOutcome,
            bytes32 auraAttestation
        )
    {
        MicroEvent storage evt = _events[eventId];
        return (
            evt.openTime,
            evt.closeTime,
            evt.settleTime,
            evt.status,
            evt.numOutcomes,
            evt.creator,
            evt.priceFeedId,
            evt.winningOutcome,
            evt.auraAttestation
        );
    }

    function isAcceptingBets(bytes32 eventId) external view returns (bool) {
        MicroEvent storage evt = _events[eventId];
        return MicroEventLib.isAcceptingBets(evt.openTime, evt.closeTime, evt.status);
    }

    // ===================== ADMIN =====================

    function setKeeper(address keeper, bool authorized) external {
        require(msg.sender == owner, "EventManager: not owner");
        authorizedKeepers[keeper] = authorized;
    }

    function setSettlementProcessor(address _sp) external {
        require(msg.sender == owner, "EventManager: not owner");
        settlementProcessor = _sp;
    }
}
