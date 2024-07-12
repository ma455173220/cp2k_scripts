#!/apps/python3/3.10.0/bin/python3
import argparse

def extract_specific_frame(input_filename, output_filename, frame_number):
    with open(input_filename, 'r') as file:
        lines = file.readlines()

    num_atoms = int(lines[0].strip())
    frames = len(lines) // (num_atoms + 2)

    if frame_number >= frames:
        print(f"Error: The specified frame number {frame_number} exceeds the total number of frames {frames}.")
        return

    start_line = frame_number * (num_atoms + 2)
    end_line = start_line + num_atoms + 2

    frame_lines = lines[start_line:end_line]

    with open(output_filename, 'w') as output_file:
        output_file.writelines(frame_lines)

    print(f"Frame {frame_number} has been successfully extracted to {output_filename}.")

def extract_frames_with_stride(input_filename, output_filename, stride):
    with open(input_filename, 'r') as file:
        lines = file.readlines()

    num_atoms = int(lines[0].strip())
    frames = len(lines) // (num_atoms + 2)

    with open(output_filename, 'w') as output_file:
        for frame_number in range(0, frames, stride):
            start_line = frame_number * (num_atoms + 2)
            end_line = start_line + num_atoms + 2
            frame_lines = lines[start_line:end_line]
            output_file.writelines(frame_lines)

    print(f"Frames with stride {stride} have been successfully extracted to {output_filename}.")

def main():
    parser = argparse.ArgumentParser(description="Extract frames from a multi-frame XYZ file.")
    parser.add_argument('-i', '--input', required=True, help="Input XYZ file containing multiple frames.")
    parser.add_argument('-o', '--output', required=True, help="Output XYZ file for the extracted frames.")
    parser.add_argument('-f', '--frame', type=int, help="Frame number to extract.")
    parser.add_argument('-s', '--stride', type=int, help="Stride for extracting frames.")

    args = parser.parse_args()

    if args.frame is not None and args.stride is not None:
        print("Error: You cannot specify both a frame number (-f) and a stride (-s).")
        return
    elif args.frame is not None:
        extract_specific_frame(args.input, args.output, args.frame)
    elif args.stride is not None:
        extract_frames_with_stride(args.input, args.output, args.stride)
    else:
        print("Error: You must specify either a frame number (-f) or a stride (-s).")

if __name__ == "__main__":
    main()

