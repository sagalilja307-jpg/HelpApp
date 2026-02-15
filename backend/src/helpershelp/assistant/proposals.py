"""Backward compatibility shim - imports from application.assistant.proposals"""
from helpershelp._deprecation import deprecated_module

deprecated_module(
    "helpershelp.assistant.proposals",
    "helpershelp.application.assistant.proposals",
    removal_version="2.0.0"
)

from helpershelp.application.assistant.proposals import (
    ProposalConfig,
    get_proposal_config,
    generate_proposals,
)

__all__ = ["ProposalConfig", "get_proposal_config", "generate_proposals"]
