import ok
import numpy as np
import json

from twisted.internet.defer import inlineCallbacks, returnValue

VOLTAGE_RANGE = (-10., 10.)
DAC_BITS = 16
N_CHANNELS = 8
CLK = 48e6 / (8.*2. + 2.)

mode_ints = {'idle': 0, 'load': 1, 'run': 2}
mode_wire = 0x00
sequence_pipe = 0x80
channel_mode_wire = 0x09
manual_voltage_wires = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]


bitfile = "dac.bit"

def time_to_ticks(clk, time):
    return max(int(abs(clk*time)), 1)

def voltage_to_signed(voltage):
    voltage_span = float(max(VOLTAGE_RANGE) - min(VOLTAGE_RANGE))
    voltage = sorted([-voltage_span, voltage, voltage_span])[1]
    return int(voltage/voltage_span*(2**DAC_BITS-1))

def voltage_to_unsigned(voltage):
    min_voltage = min(VOLTAGE_RANGE)
    max_voltage = max(VOLTAGE_RANGE)
    voltage_span = float(max(VOLTAGE_RANGE) - min(VOLTAGE_RANGE))
    voltage = sorted([min_voltage, voltage, max_voltage])[1] - min_voltage
    return int(voltage/voltage_span*(2**DAC_BITS-1))

def ramp_rate(voltage_diff, ticks):
    v = voltage_to_signed(voltage_diff)
    t = ticks
    signed_ramp_rate = int(v*2.**int(np.log2(t)-1)/t)
    if signed_ramp_rate > 0:
        return signed_ramp_rate
    else:
        return signed_ramp_rate + 2**DAC_BITS

def make_sequence_bytes(ramps):
    # break into smaller pieces [(T, loc, {dt, dv})]
    unsorted_ramps = []
    for c in range(N_CHANNELS):
        T = 0
        V = 0
        for r in ramps[c]:
            r['dt'] = time_to_ticks(CLK, r['dt'])
            unsorted_ramps.append((T, c, r))
            T += r['dt']
            T += r['dv']
        unsorted_ramps.append((T, c, {'dt': time_to_ticks(CLK, 10e-3), 'dv': -V}))
        unsorted_ramps.append((T+10e-3, c, {'dt': time_to_ticks(CLK, 10), 'dv': 0}))


    # order ramps by when the happen, then physical location on board
    sorted_ramps = sorted(unsorted_ramps)
    
    # ints to bytes
    byte_array = []
    for r in sorted_ramps:
        byte_array += [int(eval(hex(ramp_rate(r[2]['dv'], r[2]['dt']))) 
                    >> i & 0xff) for i in range(0, 16, 8)]
        byte_array += [int(eval(hex(r[2]['dt'])) 
                    >> i & 0xff) for i in range(0, 32, 8)]
    
    # add dead space
    byte_array += [0]*24
    return byte_array

def set_mode(mode):
    mode_int = mode_ints[mode]
    yield fp.SetWireInValue(mode_wire, mode_int)
    yield fp.UpdateWireIns()

def program_sequence(sequence):
    byte_array = make_sequence_bytes(sequence)
    set_mode('idle')
    set_mode('load')
    fp.WriteToPipeIn(sequence_pipe, bytearray(byte_array))
    set_mode('idle')

def start_sequence():
    set_mode('run')


if __name__ == "__main__":
    fp = ok.FrontPanel()
    device_count = fp.GetDeviceCount()
    print("{} devices connected".format(device_count))
    device_found = False
    for i in range(device_count):
        ser = fp.GetDeviceListSerial(i)
        fp.OpenBySerial(ser)
        id = fp.GetDeviceID()
        print("Checking {}".format(id))
        if "KRbtest1" in id:
            print("Connecting to {}".format(id))
            device_found = True
            break
    if device_found:
        fp.ConfigureFPGA(bitfile)
        print("Bitfile loaded!")

        ramps = [
            [{'dv':1, 'dt':1}, {'dv':0, 'dt':3}],
            [{'dv':1, 'dt':1}],
            [{'dv':1, 'dt':1}],
            [{'dv':1, 'dt':1}],
            [{'dv':1, 'dt':1}],
            [{'dv':1, 'dt':1}],
            [{'dv':1, 'dt':1}],
            [{'dv':1, 'dt':1}]
        ]

        print("Programming sequence")
        program_sequence(ramps)
        print("Running sequence")
        start_sequence()
        print("Done!")
        