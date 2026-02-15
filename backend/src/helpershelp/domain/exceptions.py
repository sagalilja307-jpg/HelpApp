"""Domain-specific exceptions - pure Python, no external dependencies"""


class DomainException(Exception):
    """Base exception for domain layer"""
    pass


class ValidationError(DomainException):
    """Raised when domain validation rules are violated"""
    pass


class ItemNotFoundError(DomainException):
    """Raised when an item cannot be found"""
    pass


class ProposalExpiredError(DomainException):
    """Raised when attempting to act on an expired proposal"""
    pass
