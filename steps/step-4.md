VETRA Depth Recorder: Session Validation and Point Cloud Export
To verify a captured VETRA session and visualize its 3D structure, we provide a Python script (vetra_validate.py) that reads the session metadata and per-frame data, reconstructs 3D point clouds from the depth images, and optionally saves them as PLY files. The script performs the following tasks:
	Load session and frame metadata: Parse session_meta.json and each frame_XXXX/meta.json to obtain file paths, camera intrinsics (fx, fy, cx, cy, image size), and the 4×4 camera-to-world pose matrix for each frame.
	Load depth (and color): Read the raw depth image (depth.bin) as a NumPy array of uint16 values (in millimeters). Optionally load the aligned color image (color.jpg) for coloring the point cloud.
	Backproject to 3D: Using the standard pinhole camera model, convert each pixel with depth d (in meters) at image coordinates (u,v) into a 3D point. The equations are:
	z=d/1000, x=(u-cx) z/fx, y=(v-cy) z/fy,
	where we divide by 1000.0 to convert millimeters to meters. This formula is confirmed by the Open3D documentation[1]. The resulting point (x,y,z) is in the camera frame, and we transform it to the world frame by the given pose (camera-to-world matrix).
	Validation and statistics: Check for missing files or mismatches (e.g. expected depth width/height vs actual file size). Compute summary stats (frame count, global min/max depth, intrinsics consistency).
	Point Cloud export: If requested via --output-ply, the script uses Open3D (if installed) to create point clouds. With Open3D, we can use create_point_cloud_from_rgbd_image or create_point_cloud_from_depth_image to handle projection and write the PLY file easily[1][2]. Otherwise, the script manually projects points with NumPy and writes a PLY file in ASCII format.
Dependencies
	Python 3 with the argparse, json, and os modules (standard library).
	NumPy for numerical array handling.
	Pillow (the PIL package) to load color images (optional, for colored point clouds).
	Open3D (optional but recommended) for easy point-cloud creation and I/O. Install via pip install open3d. If Open3D is not available, the script falls back to a manual PLY writer.
For example, install dependencies with:
pip install numpy pillow open3d
Processing Steps (Script Outline)
	Parse arguments: Use argparse to get --input /path/to/session_meta.json, --output-ply [path], and --summary-only flags.
	Load session metadata: Open the given session_meta.json. Determine the session directory and list all frame subdirectories (either from JSON or by scanning the session folder).
	Iterate frames: For each frame directory (e.g. frame_0001):
	Load its meta.json. Extract intrinsics (fx, fy, cx, cy, width, height), pose matrix (4×4 camera-to-world), and file paths for color and depth.
	Validate files: Check that color.jpg, depth.bin, and meta.json exist. Read the depth file with np.fromfile(..., dtype=np.uint16) and reshape to (height, width). Verify the file size matches width*height.
	Compute statistics: Update global counters for min/max depth values. If intrinsics vary between frames, note this in a warning.
	Point cloud generation (if not summary-only):
	With Open3D: Create open3d.geometry.Image objects for color and depth, then an RGBDImage via create_from_color_and_depth, using depth_scale=1000.0. Construct a PinholeCameraIntrinsic from the intrinsics. Call open3d.geometry.PointCloud.create_from_rgbd_image(rgbd, intrinsic, extrinsic=pose)[3], which applies the same projection formulas[1] and the camera-to-world extrinsic.
	Without Open3D: Manually backproject each pixel with valid depth: let (u,v) be a grid of image coordinates and d = depth[v,u]/1000.0. Compute X = (u-cx)*d/fx, Y = (v-cy)*d/fy, Z = d. Stack into a (3×N) array, transform by the pose matrix, and (optionally) attach colors.
	Save PLY: If --output-ply is specified, write the point cloud to a PLY file. If the output path ends in “.ply”, the script can combine all frames into one file; otherwise, it treats it as a directory and writes one PLY per frame. Open3D’s write_point_cloud writes binary or ASCII PLY[2].
	Summary output: After processing, print the number of frames, the (global) depth range, and note if any validation checks failed.
This ensures each session’s data is correctly formatted and allows offline 3D fusion or visualization. In the implementation below, careful error checks are included for missing files and shape mismatches.
#!/usr/bin/env python3
"""
vetra_validate.py: Validate VETRA depth recorder session and optionally export point clouds.
"""

import argparse
import json
import os
import sys

import numpy as np
try:
    import open3d as o3d
    have_o3d = True
except ImportError:
    have_o3d = False

from PIL import Image


def parse_args():
    parser = argparse.ArgumentParser(
        description='Validate VETRA session and export 3D point clouds (PLY).'
    )
    parser.add_argument('--input', required=True,
                        help='Path to session_meta.json')
    parser.add_argument('--output-ply', default=None,
                        help='Output PLY file or directory (optional)')
    parser.add_argument('--summary-only', action='store_true',
                        help='Only print summary info (no PLY output)')
    return parser.parse_args()


def load_json(path):
    if not os.path.isfile(path):
        raise FileNotFoundError(f"JSON file not found: {path}")
    with open(path, 'r') as f:
        return json.load(f)


def backproject_depth(depth, fx, fy, cx, cy):
    """Backproject a depth image (H×W) into camera-space points (H×W×3)."""
    H, W = depth.shape
    # Create pixel grid
    u = np.arange(W)
    v = np.arange(H)
    uu, vv = np.meshgrid(u, v)
    # Convert depth to meters
    z = depth.astype(np.float32) / 1000.0
    # Apply pinhole model
    x = (uu - cx) * z / fx
    y = (vv - cy) * z / fy
    # Stack and flatten
    points = np.stack((x, y, z), axis=-1)  # shape (H, W, 3)
    return points.reshape(-1, 3)  # (N,3)


def write_ply_manual(filename, points, colors=None):
    """Write points (and optional colors) to a PLY file in ASCII format."""
    assert points.ndim == 2 and points.shape[1] == 3
    n = points.shape[0]
    has_color = (colors is not None)
    header = [
        "ply",
        "format ascii 1.0",
        f"element vertex {n}",
        "property float x",
        "property float y",
        "property float z"
    ]
    if has_color:
        header += ["property uchar red", "property uchar green", "property uchar blue"]
    header.append("end_header")
    with open(filename, 'w') as f:
        f.write("\n".join(header) + "\n")
        if has_color:
            for (x, y, z), (r, g, b) in zip(points, colors):
                f.write(f"{x} {y} {z} {r} {g} {b}\n")
        else:
            for x, y, z in points:
                f.write(f"{x} {y} {z}\n")


def main():
    args = parse_args()
    session_meta = load_json(args.input)
    session_dir = os.path.dirname(os.path.abspath(args.input))

    # Determine frame directories
    frames = []
    # Try session_meta to list frames, else scan directory
    if 'frames' in session_meta and isinstance(session_meta['frames'], list):
        frames = [f.get('frameId', None) for f in session_meta['frames'] if 'frameId' in f]
    if not frames:
        # find subdirectories named 'frame_XXXX'
        frames = sorted([d for d in os.listdir(session_dir)
                         if os.path.isdir(os.path.join(session_dir, d)) and d.startswith('frame_')])
    if not frames:
        print("No frame directories found in session.")
        sys.exit(1)

    # Prepare output
    output_path = args.output_ply
    save_combined = False
    if output_path:
        if output_path.lower().endswith('.ply'):
            save_combined = True
            combined_points = []
            combined_colors = []
        else:
            # treat output path as directory
            os.makedirs(output_path, exist_ok=True)

    total_frames = 0
    depth_min, depth_max = float('inf'), 0.0
    ref_intrinsics = None

    for frame_id in frames:
        frame_dir = os.path.join(session_dir, frame_id)
        meta_path = os.path.join(frame_dir, 'meta.json')
        try:
            meta = load_json(meta_path)
        except FileNotFoundError:
            print(f"Warning: meta.json not found for {frame_id}, skipping.")
            continue

        total_frames += 1
        print(f"Processing frame {frame_id}...")
        fx = meta['intrinsics']['fx']
        fy = meta['intrinsics']['fy']
        cx = meta['intrinsics']['cx']
        cy = meta['intrinsics']['cy']
        W = meta['intrinsics']['imageWidth']
        H = meta['intrinsics']['imageHeight']
        pose = np.array(meta['pose']).reshape((4, 4))  # camera-to-world

        # Check intrinsics consistency
        if ref_intrinsics is None:
            ref_intrinsics = (fx, fy, cx, cy, W, H)
        else:
            if (fx, fy, cx, cy, W, H) != ref_intrinsics:
                print(f"  [Warning] Intrinsics differ in {frame_id}")

        # Load depth
        depth_path = os.path.join(frame_dir, meta.get('depthPath', 'depth.bin'))
        if not os.path.isfile(depth_path):
            print(f"  [Error] Depth file not found: {depth_path}")
            continue
        depth = np.fromfile(depth_path, dtype=np.uint16)
        if depth.size != W * H:
            print(f"  [Error] Depth file size mismatch for {frame_id}: expected {W*H}, got {depth.size}")
            continue
        depth = depth.reshape((H, W))
        dmin, dmax = depth.min(), depth.max()
        depth_min = min(depth_min, float(dmin))
        depth_max = max(depth_max, float(dmax))

        # Load color (optional)
        color = None
        color_path = os.path.join(frame_dir, meta.get('imagePath', 'color.jpg'))
        if os.path.isfile(color_path):
            color = Image.open(color_path)
            color = color.convert('RGB')
            color_np = np.asarray(color)
            if color_np.shape[:2] != (H, W):
                print(f"  [Warning] Color image size mismatch in {frame_id}")
                color = None
        else:
            print(f"  [Warning] Color image not found for {frame_id}")

        if not args.summary_only:
            # Generate point cloud
            if have_o3d:
                # Create Open3D RGBD image
                depth_o3d = o3d.geometry.Image(depth.astype(np.float32))
                if color is not None:
                    color_o3d = o3d.geometry.Image(color_np)
                    # Note: Open3D expects depth_scale inverse of our units (we already used meters)
                    rgbd = o3d.geometry.RGBDImage.create_from_color_and_depth(
                        color_o3d, depth_o3d, depth_scale=1000.0, convert_rgb_to_intensity=False)
                else:
                    # Create dummy color if needed (grayscale)
                    gray = Image.fromarray((depth / depth.max() * 255).astype(np.uint8))
                    color_o3d = o3d.geometry.Image(np.asarray(gray))
                    rgbd = o3d.geometry.RGBDImage.create_from_color_and_depth(
                        color_o3d, depth_o3d, depth_scale=1000.0, convert_rgb_to_intensity=True)

                # Build camera intrinsics
                intrinsic = o3d.camera.PinholeCameraIntrinsic(W, H, fx, fy, cx, cy)
                # Use pose (camera-to-world) as extrinsic
                extrinsic = pose
                # Create point cloud (this applies backprojection internally)
                pcd = o3d.geometry.PointCloud.create_from_rgbd_image(
                    rgbd, intrinsic, extrinsic)
                if save_combined:
                    # Accumulate points and colors
                    pts = np.asarray(pcd.points)
                    combined_points.append(pts)
                    if pcd.has_colors():
                        combined_colors.append(np.asarray(pcd.colors) * 255)
                else:
                    # Save per-frame PLY
                    if output_path:
                        out_file = output_path
                        if os.path.isdir(output_path):
                            out_file = os.path.join(output_path, f"{frame_id}.ply")
                        o3d.io.write_point_cloud(out_file, pcd)
            else:
                # Manual backprojection
                pts_cam = backproject_depth(depth, fx, fy, cx, cy)
                # Filter out zero-depth points
                valid = (pts_cam[:, 2] > 0)
                pts_cam = pts_cam[valid]
                # Transform to world coordinates
                pts_cam_h = np.hstack((pts_cam, np.ones((pts_cam.shape[0], 1))))
                pts_world = (pose @ pts_cam_h.T).T[:, :3]
                # Handle colors if available
                colors_list = None
                if color is not None:
                    colors_flat = color_np.reshape(-1, 3)
                    colors_list = (colors_flat[valid]).astype(np.uint8)
                if save_combined:
                    combined_points.append(pts_world)
                    if colors_list is not None:
                        combined_colors.append(colors_list)
                else:
                    if output_path:
                        out_file = output_path
                        if os.path.isdir(output_path):
                            out_file = os.path.join(output_path, f"{frame_id}.ply")
                        write_ply_manual(out_file, pts_world, colors_list)

    # After all frames, output summary
    print(f"\nProcessed {total_frames} frames.")
    if total_frames > 0:
        print(f"Depth range: {depth_min:.2f} to {depth_max:.2f} (uint16 raw units)")
    if args.summary_only:
        return

    # If combining into one PLY
    if save_combined and output_path:
        if combined_points:
            all_points = np.vstack(combined_points)
            all_colors = None
            if combined_colors:
                all_colors = np.vstack(combined_colors)
            print(f"Saving combined point cloud to {output_path}...")
            # Save using Open3D if available
            if have_o3d:
                pcd_all = o3d.geometry.PointCloud()
                pcd_all.points = o3d.utility.Vector3dVector(all_points)
                if all_colors is not None:
                    pcd_all.colors = o3d.utility.Vector3dVector(all_colors.astype(np.float64)/255.0)
                o3d.io.write_point_cloud(output_path, pcd_all)
            else:
                write_ply_manual(output_path, all_points, all_colors)

if __name__ == '__main__':
    main()
This script performs the full validation and optional export. It first loads JSON metadata and checks for file consistency. It then backprojects each depth image to 3D using the intrinsics and pose (using the well-known formulas from the pinhole camera model[1]). If Open3D is available, we exploit its create_point_cloud_from_rgbd_image function to handle projection and PLY writing[3][2]. Otherwise, it manually computes and writes PLY. Running with --summary-only will print counts and depth ranges without generating any point cloud files.
Usage example:
python vetra_validate.py --input /path/to/session_meta.json --output-ply output_dir
This would read the session, verify contents, and save one PLY per frame into output_dir. To create one merged PLY for the entire session, use a filename:
python vetra_validate.py --input /path/to/session_meta.json --output-ply session_all.ply
Dependencies: ensure numpy, Pillow, and optionally open3d are installed. The Open3D-based method internally uses the formulas shown above for backprojection[1] and writes PLY via open3d.io.write_point_cloud[2], guaranteeing compatibility with standard 3D tools.
Sources: We follow the standard depth-to-3D projection formulas from Open3D’s documentation[1], and use Open3D’s I/O functions for ease of writing PLY files[2].
________________________________________
[1] open3d.geometry.create_point_cloud_from_depth_image — Open3D 0.7.0 documentation
https://www.open3d.org/docs/0.7.0/python_api/open3d.geometry.create_point_cloud_from_depth_image.html
[2] open3d.io.write_point_cloud - Open3D primary (unknown) documentation
https://www.open3d.org/docs/latest/python_api/open3d.io.write_point_cloud.html
[3] open3d.geometry.create_point_cloud_from_rgbd_image — Open3D 0.6.0 documentation
https://www.open3d.org/docs/0.6.0/python_api/open3d.geometry.create_point_cloud_from_rgbd_image.html
