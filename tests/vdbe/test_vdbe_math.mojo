from src.core.types import *
from src.engine.row import Value
from src.vdbe.opcode import *
from src.vdbe.vm import Vdbe, VDBE_RESULT_ROW, VDBE_RESULT_DONE


def test_vdbe_arithmetic_and_control_flow() raises:
    print("=== Testing VDBE Arithmetic & Jump Execution ===")
    
    # Calculate: (10 + 25) * 2 = 70
    var vm = Vdbe()
    vm.add_opcode(Opcode(OP_INTEGER, 10, 1))       # r1 = 10
    vm.add_opcode(Opcode(OP_INTEGER, 25, 2))       # r2 = 25
    vm.add_opcode(Opcode(OP_ADD, 1, 2, 3))         # r3 = r1 + r2 (35)
    vm.add_opcode(Opcode(OP_INTEGER, 2, 4))        # r4 = 2
    vm.add_opcode(Opcode(OP_MULTIPLY, 3, 4, 5))    # r5 = r3 * r4 (70)
    vm.add_opcode(Opcode(OP_RESULT_ROW, 5, 1))     # Output r5
    vm.add_opcode(Opcode(OP_HALT))

    var rc = vm.step()
    if rc != VDBE_RESULT_ROW:
        raise Error("Expected VDBE_RESULT_ROW, got " + String(rc))

    var row = vm.current_result_row()
    if len(row) != 1 or row[0].to_int() != 70:
        raise Error("VDBE arithmetic result mismatch: " + String(row[0].to_int()))

    var rc_done = vm.step()
    if rc_done != VDBE_RESULT_DONE:
        raise Error("Expected VDBE_RESULT_DONE, got " + String(rc_done))

    print("VDBE arithmetic & control flow passed successfully!")


def main() raises:
    test_vdbe_arithmetic_and_control_flow()
