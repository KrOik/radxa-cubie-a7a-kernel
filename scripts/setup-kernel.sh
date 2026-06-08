#!/bin/bash
# Enhanced setup script with board parameter support
set -uo pipefail

BOARD="${1:-a7a}"
BSP="${2:-allwinner-bsp-1.4.8}"
KERNEL="${3:-kernel-6.6}"
DEVICE="${4:-allwinner-device-1.4.8}"

echo "Setting up kernel tree for board: ${BOARD}..."

# Validate board type
if [[ ! "$BOARD" =~ ^(a7a|a7z)$ ]]; then
    echo "Error: Invalid board type. Use 'a7a' or 'a7z'"
    exit 1
fi

# 1. BSP symlink
if [ ! -L "$KERNEL/bsp" ]; then
    ln -sfn "$(pwd)/$BSP" "$KERNEL/bsp"
    echo "[1/5] BSP symlink created"
else
    echo "[1/5] BSP symlink already exists"
fi

# 2. Copy DTS/DTSI files
DTS_DIR="$KERNEL/arch/arm64/boot/dts/allwinner"
echo "[2/5] Copying DTS files..."

# Copy base DTSI files if they exist
if [ -f "$BSP/configs/linux-6.6/sun60iw2p1.dtsi" ]; then
    cp "$BSP/configs/linux-6.6/sun60iw2p1.dtsi" "$DTS_DIR/" || true
fi
if [ -f "$BSP/configs/linux-6.6/sun60iw2p1-cpu-vf.dtsi" ]; then
    cp "$BSP/configs/linux-6.6/sun60iw2p1-cpu-vf.dtsi" "$DTS_DIR/" || true
fi

# Board-specific DTS
if [ -f "$DEVICE/configs/cubie_${BOARD}/linux-6.6/board.dts" ]; then
    echo "Using upstream board.dts for ${BOARD}"
    cp "$DEVICE/configs/cubie_${BOARD}/linux-6.6/board.dts" \
       "$DTS_DIR/sun60i-a733-cubie-${BOARD}.dts"
elif [ -f "configs/board-overclocked.dts" ]; then
    echo "Using project board-overclocked.dts for ${BOARD}"
    cp "configs/board-overclocked.dts" \
       "$DTS_DIR/sun60i-a733-cubie-${BOARD}.dts"
elif [ -f "$DEVICE/configs/cubie_a7a/linux-6.6/board.dts" ]; then
    echo "Warning: No ${BOARD} board.dts found, using A7A as template"
    cp "$DEVICE/configs/cubie_a7a/linux-6.6/board.dts" \
       "$DTS_DIR/sun60i-a733-cubie-${BOARD}.dts"
else
    echo "Error: Cannot find any board.dts file!"
    exit 1
fi

# Copy overclocked DTSI if available
if [ -f "configs/sun60iw2p1-cpu-vf-overclocked.dtsi" ]; then
    cp "configs/sun60iw2p1-cpu-vf-overclocked.dtsi" "$DTS_DIR/"
    echo "Copied overclocked CPU DTSI"
fi

if [ -f "configs/sun60iw2p1-gpu-overclocked.dtsi" ]; then
    cp "configs/sun60iw2p1-gpu-overclocked.dtsi" "$DTS_DIR/"
    echo "Copied overclocked GPU DTSI"
fi

# Add to Makefile if not present
if ! grep -q "sun60i-a733-cubie-${BOARD}" "$DTS_DIR/Makefile"; then
    echo "dtb-\$(CONFIG_ARCH_SUNXI) += sun60i-a733-cubie-${BOARD}.dtb" >> "$DTS_DIR/Makefile"
    echo "Added ${BOARD} to DTS Makefile"
fi

echo "[2/5] DTS files copied"

# 3. Copy dt-bindings headers
echo "[3/5] Copying dt-bindings headers..."
INC="$KERNEL/include/dt-bindings"
mkdir -p "$INC/spi" "$INC/display"

cp -u "$BSP/include/dt-bindings/clock/sun60iw2-"*.h "$INC/clock/" 2>/dev/null || true
cp -u "$BSP/include/dt-bindings/clock/sunxi-clk.h" "$INC/clock/" 2>/dev/null || true
cp -u "$BSP/include/dt-bindings/clock/sunxi-ccu.h" "$INC/clock/" 2>/dev/null || true
cp -u "$BSP/include/dt-bindings/reset/sun60iw2-"*.h "$INC/reset/" 2>/dev/null || true
cp -u "$BSP/include/dt-bindings/power/sun60iw2-power.h" "$INC/power/" 2>/dev/null || true
cp -u "$BSP/include/dt-bindings/display/sunxi-lcd.h" "$INC/display/" 2>/dev/null || true
cp -u "$BSP/include/dt-bindings/display/lcd_command.h" "$INC/display/" 2>/dev/null || true
cp -u "$BSP/include/dt-bindings/gpio/sun4i-gpio.h" "$INC/gpio/" 2>/dev/null || true
cp -u "$BSP/include/dt-bindings/spi/sunxi-spi.h" "$INC/spi/" 2>/dev/null || true

echo "[3/5] dt-bindings headers copied"

# 4. Create auto-generated BSP header if missing
if [ ! -f "$BSP/include/sunxi-autogen.h" ]; then
    cat > "$BSP/include/sunxi-autogen.h" <<'HEADER'
/* Auto-generated BSP version header */
#ifndef _SUNXI_AUTOGEN_H
#define _SUNXI_AUTOGEN_H
#define AW_BSP_VERSION "cubie-aiot-v1.4.8-custom"
#endif
HEADER
    echo "[4/5] Created sunxi-autogen.h"
else
    echo "[4/5] sunxi-autogen.h already exists"
fi

# 5. Configure
cd "$KERNEL"

DEFCONFIG="cubie_a7a_defconfig"
if [ -f "../configs/a7z/cubie_a7z_defconfig" ] && [ "$BOARD" = "a7z" ]; then
    DEFCONFIG="cubie_a7z_defconfig"
    cp "../configs/a7z/cubie_a7z_defconfig" arch/arm64/configs/
    echo "[5/5] Installed A7Z defconfig"
elif [ -f "../configs/cubie_a7a_defconfig" ]; then
    cp "../configs/cubie_a7a_defconfig" arch/arm64/configs/
    echo "[5/5] Installed defconfig from project"
else
    echo "[5/5] Using default defconfig"
fi

echo ""
echo "✅ Kernel tree setup complete for board: ${BOARD}"
echo ""
echo "Next steps:"
echo "  cd $KERNEL"
echo "  make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- BSP_TOP=bsp/ ${DEFCONFIG}"
echo "  make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- BSP_TOP=bsp/ -j\$(nproc) Image dtbs modules"
