OUTPUT_FORMAT("elf32-littleriscv")

__stack_size = 2048;

__dmem_origin = 0x00000000;
__dmem_size   = 0x00010000; /* 64KB total DMEM */
__boot_ram_origin = 0x0000E000;
__app_ram_size = __boot_ram_origin - __dmem_origin; /* 56KB reserved for app */

MEMORY {
    RAM (xrw)       : ORIGIN = __dmem_origin, LENGTH = __app_ram_size
    FLASH (rx)      : ORIGIN = 0x01100000, LENGTH = 0x00010000 /* 64KB */
}

SECTIONS {

    /* CODE SECTION: FLASH */
    .text :
    {
        . = ALIGN(4);

        KEEP(*(.vectors))    /* reset/IRQ vectors: reset at +0x00, IRQ at +0x10 */
        KEEP(*(.text.entry)) /* startupcode section */
        
        *(.text)           /* Code */
        *(.text*)
        *(.rodata)         /* Read-only data (const) */
        *(.rodata*)
        *(.srodata)
        *(.srodata*)
        . = ALIGN(4);
        _etext = .;        /* End of code in Flash */
        _sidata = _etext;  /* Start of initialized data in Flash (LMA) */
    } >FLASH


    /* INITIALIZED DATA SECTION: RAM (VMA) loaded from FLASH (LMA) */
    .data : AT ( _sidata )
    {
        . = ALIGN(4);
        _sdata = .;        /* Start of data in RAM */
        _ram_start = .;
        
        *(.data)
        *(.data*)
        *(.sdata)
        *(.sdata*)
        
        . = ALIGN(4);
        /* GP (Global Pointer) optimization for RISC-V */
        PROVIDE(__global_pointer$ = . + 0x800); 

        . = ALIGN(4);
        _edata = .;        /* End of data in RAM */
    } >RAM

    /* UNINITIALIZED DATA SECTION: RAM */
    .bss (NOLOAD) :
    {
        . = ALIGN(4);
        _sbss = .;         /* Start of BSS */
        *(.bss)
        *(.bss*)
        *(.sbss)
        *(.sbss*)
        *(COMMON)

        . = ALIGN(4);
        _ebss = .;         /* End of BSS */
    } >RAM

    /* HEAP SECTION: RAM */
    .heap (NOLOAD) :
    {
        . = ALIGN(8);
        _end = .;          /* Standard symbol for 'end of static RAM', used by _sbrk */
        _heap_start = .;   /* Explicit heap start symbol */
        
    } >RAM

    /* STACK SECTION: RAM */
    .stack (NOLOAD) :
    {
        . = ALIGN(16);     /* Stack RISC-V nên align 16 byte */
        _stack_bottom = .; /* Điểm thấp nhất của Stack */
        
        . = . + __stack_size; /* Dành chỗ cho Stack */
        
        . = ALIGN(16);
        _stack_top = .;    /* Đỉnh Stack (nơi SP trỏ tới ban đầu) */
        _estack = _stack_top; /* Symbol chuẩn cho startup code */
    } >RAM

    /* KIỂM TRA LỖI (User Check)
     * Kiểm tra xem Stack có bị tràn ra ngoài RAM không?
     * Kiểm tra xem Heap có còn không gian không?
     */
    ASSERT(_stack_bottom >= _heap_start, "Error: RAM overflow! No room left for Heap between BSS and Stack.")
    ASSERT(_estack <= ORIGIN(RAM) + LENGTH(RAM), "Error: App RAM overflow into bootloader reserved RAM.")

    /DISCARD/ : {
        *(.comment)
        *(.eh_frame)
    }
}

ENTRY(_start)
