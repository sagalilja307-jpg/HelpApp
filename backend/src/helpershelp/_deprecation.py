"""Deprecation utilities for backward compatibility shims"""
import warnings
from functools import wraps
from typing import Any, Callable


def deprecated_module(old_path: str, new_path: str, removal_version: str = "2.0.0") -> None:
    """
    Emit a deprecation warning for module imports.
    
    Args:
        old_path: The deprecated import path (e.g., "helpershelp.assistant.scoring")
        new_path: The new import path (e.g., "helpershelp.domain.rules.scoring")
        removal_version: Version when the deprecated path will be removed
    """
    message = (
        f"\n{'='*80}\n"
        f"DEPRECATION WARNING\n"
        f"{'='*80}\n"
        f"Module '{old_path}' is deprecated and will be removed in version {removal_version}.\n"
        f"Please update your imports to use:\n"
        f"  from {new_path} import ...\n"
        f"{'='*80}\n"
    )
    warnings.warn(message, DeprecationWarning, stacklevel=3)


def deprecated_function(old_name: str, new_path: str, removal_version: str = "2.0.0") -> Callable:
    """
    Decorator to mark functions as deprecated.
    
    Args:
        old_name: The deprecated function name
        new_path: The new location to use
        removal_version: Version when the function will be removed
    """
    def decorator(func: Callable) -> Callable:
        @wraps(func)
        def wrapper(*args: Any, **kwargs: Any) -> Any:
            message = (
                f"\n{'='*80}\n"
                f"DEPRECATION WARNING\n"
                f"{'='*80}\n"
                f"Function '{old_name}' is deprecated and will be removed in version {removal_version}.\n"
                f"Please use: {new_path}\n"
                f"{'='*80}\n"
            )
            warnings.warn(message, DeprecationWarning, stacklevel=2)
            return func(*args, **kwargs)
        return wrapper
    return decorator
