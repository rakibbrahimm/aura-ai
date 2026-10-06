import ast
import datetime
import math
import operator
import platform
import os

_ALLOWED = {
    ast.Add: operator.add,
    ast.Sub: operator.sub,
    ast.Mult: operator.mul,
    ast.Div: operator.truediv,
    ast.FloorDiv: operator.floordiv,
    ast.Mod: operator.mod,
    ast.Pow: operator.pow,
    ast.USub: operator.neg,
    ast.UAdd: operator.pos,
}

def _eval(node):
    if isinstance(node, ast.Expression):
        return _eval(node.body)

    if isinstance(node, ast.Constant):
        if isinstance(node.value, (int, float)):
            return node.value
        raise ValueError("invalid constant")

    if isinstance(node, ast.BinOp):
        op = type(node.op)
        if op not in _ALLOWED:
            raise ValueError("operator not allowed")
        left = _eval(node.left)
        right = _eval(node.right)

        if op is ast.Pow and abs(right) > 100:
            raise ValueError("power too large")

        return _ALLOWED[op](left, right)

    if isinstance(node, ast.UnaryOp):
        op = type(node.op)
        if op not in _ALLOWED:
            raise ValueError("operator not allowed")
        return _ALLOWED[op](_eval(node.operand))

    raise ValueError("expression not allowed")

def calculator(expression):
    expression = expression.strip()

    if len(expression) > 200:
        raise ValueError("expression too long")

    tree = ast.parse(expression, mode="eval")
    result = _eval(tree)

    if isinstance(result, float) and not math.isfinite(result):
        raise ValueError("invalid result")

    return result

def system_info():
    return {
        "platform": platform.platform(),
        "python": platform.python_version(),
        "machine": platform.machine(),
        "processor": platform.processor(),
        "pid": os.getpid()
    }

def current_time():
    now = datetime.datetime.now()
    return {
        "date": now.strftime("%Y-%m-%d"),
        "time": now.strftime("%H:%M:%S"),
        "day": now.strftime("%A")
    }
