import os
from pathlib import Path

def convert_hex_to_mem():
    # 1. Xác định cấu trúc thư mục tự động
    # Path(__file__).resolve() lấy đường dẫn tuyệt đối của file script này
    current_script_path = Path(__file__).resolve()
    
    # Từ thư mục 'python_pg', nhảy lên 1 cấp để vào 'Beta_AISoC.srcs'
    srcs_root = current_script_path.parent.parent
    
    # Định nghĩa các đường dẫn dựa trên cấu trúc bạn cung cấp
    input_path = srcs_root / "sources_1" / "new" / "boot_AISoC.hex"
    output_path = srcs_root / "sim_1" / "new" / "W25Q128JVxIM.mem"
    
    # Kiểm tra xem file hex đầu vào có tồn tại không
    if not input_path.exists():
        print(f"Lỗi: Không tìm thấy file hex tại: {input_path}")
        return

    print(f"Đang đọc file: {input_path}")
    print(f"Đang chuẩn bị ghi vào: {output_path}")

    # 2. Xử lý dữ liệu (giữ nguyên logic fix cứng 16MB)
    TOTAL_SIZE = 16 * 1024 * 1024 
    data_bytes = []
    
    with open(input_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line: continue
            for i in range(0, len(line), 2):
                byte = line[i:i+2]
                if len(byte) == 2:
                    data_bytes.append(byte.lower())

    # Fill 'ff'
    if len(data_bytes) < TOTAL_SIZE:
        data_bytes.extend(['ff'] * (TOTAL_SIZE - len(data_bytes)))
    else:
        data_bytes = data_bytes[:TOTAL_SIZE]

    # 3. Ghi file mem (tự động tạo thư mục nếu chưa có)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    header = "/* Contents of Memory Array starting from address 0.  This is a standard Verilog readmemh format. */\n"
    with open(output_path, 'w') as f:
        f.write(header)
        for i in range(0, len(data_bytes), 16):
            chunk = data_bytes[i:i+16]
            f.write(" ".join(chunk) + " \n")

    print(f"Thành công! Đã cập nhật file mem tại {output_path.name}")

if __name__ == "__main__":
    convert_hex_to_mem()