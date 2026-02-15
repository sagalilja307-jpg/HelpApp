"""Backward compatibility shim - imports from application.assistant.proposals"""
from helpershelp.application.assistant.proposals import (
    ProposalConfig,
    get_proposal_config,
    generate_proposals,
    decide_proposal,
)

__all__ = ["ProposalConfig", "get_proposal_config", "generate_proposals", "decide_proposal"]
