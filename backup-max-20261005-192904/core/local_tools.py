import ast
import operator
from datetime import datetime

_ALLOWED = {
    ast.Add: operator.add,
    ast.Sub: operator.sub,
    ast.Mult: operator.mul,
    ast.Div: operator.truediv,
    ast.Mod: operator.mod,
    ast.Pow: operator.pow,
    ast.USub: operator.neg,
    ast.UAdd: operator.pos,
}


def calculate(expression):
    expression = expression.strip()

    if len(expression) > 100:
        raise ValueError("Expression too long")

    tree = ast.parse(expression, mode="eval")

    def evaluate(node):
        if isinstance(node, ast.Constant):
            if isinstance(node.value, (int, float)):
                return node.value
            raise ValueError("Invalid value")

        if isinstance(node, ast.BinOp):
            operation = _ALLOWED.get(type(node.op))
            if not operation:
                raise ValueError("Operator not allowed")
            return operation(
                evaluate(node.left),
                evaluate(node.right)
            )

        if isinstance(node, ast.UnaryOp):
            operation = _ALLOWED.get(type(node.op))
            if not operation:
                raise ValueError("Operator not allowed")
            return operation(evaluate(node.operand))

        raise ValueError("Only basic arithmetic is supported")

    result = evaluate(tree.body)

    if isinstance(result, float) and result.is_integer():
        return int(result)

    return result


def now():
    return datetime.now().astimezone().isoformat()


def run_tool(name, argument):
    if name == "calculator":
        return str(calculate(argument))

    if name == "time":
        return now()

    raise ValueError("Unknown local tool")
