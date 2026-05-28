#!/usr/bin/env bash

_beta_aisoc_builder()
{
    local cur prev opts
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD - 1]}"
    opts="--target --max-flash-kb --help"

    COMPREPLY=()

    case "$prev" in
        --target)
            COMPREPLY=($(compgen -W "app bootloader test_unit both" -- "$cur"))
            return
            ;;
        --max-flash-kb)
            COMPREPLY=($(compgen -W "64 128 256 512 1024" -- "$cur"))
            return
            ;;
    esac

    # Pressing Tab right after ./scripts/builder.py should show available options.
    COMPREPLY=($(compgen -W "$opts" -- "$cur"))
}

_beta_aisoc_host_flasher()
{
    local cur opts default_fw
    cur="${COMP_WORDS[COMP_CWORD]}"
    opts="--debug --chunk-size --boot-timeout --write-timeout --write-delay --monitor --monitor-only --terminal-only --monitor-timeout --monitor-format --monitor-input --monitor-newline --monitor-baud --monitor-accuracy --accuracy-input --accuracy-labels --accuracy-count --accuracy-skip --accuracy-input-layout --accuracy-chunk-size --accuracy-timeout --accuracy-run-timeout --accuracy-retries --accuracy-inter-frame-delay --accuracy-tx-slice-size --accuracy-tx-slice-delay --accuracy-progress-every --accuracy-command --help"
    default_fw="Build/main.bin"

    COMPREPLY=()

    if [[ "${COMP_WORDS[COMP_CWORD - 1]}" == "--chunk-size" ]]; then
        COMPREPLY=($(compgen -W "32 64 128 256" -- "$cur"))
        return
    fi

    if [[ "${COMP_WORDS[COMP_CWORD - 1]}" == "--write-timeout" ]]; then
        COMPREPLY=($(compgen -W "2.0 5.0 10.0 30.0" -- "$cur"))
        return
    fi

    if [[ "${COMP_WORDS[COMP_CWORD - 1]}" == "--boot-timeout" ]]; then
        COMPREPLY=($(compgen -W "2.0 5.0 10.0 30.0" -- "$cur"))
        return
    fi

    if [[ "${COMP_WORDS[COMP_CWORD - 1]}" == "--write-delay" ]]; then
        COMPREPLY=($(compgen -W "0 0.001 0.003 0.005" -- "$cur"))
        return
    fi

    if [[ "${COMP_WORDS[COMP_CWORD - 1]}" == "--monitor-timeout" ]]; then
        COMPREPLY=($(compgen -W "0 5 10 30 60" -- "$cur"))
        return
    fi

    if [[ "${COMP_WORDS[COMP_CWORD - 1]}" == "--monitor-format" ]]; then
        COMPREPLY=($(compgen -W "ascii hex" -- "$cur"))
        return
    fi

    if [[ "${COMP_WORDS[COMP_CWORD - 1]}" == "--monitor-input" ]]; then
        COMPREPLY=($(compgen -W "char line" -- "$cur"))
        return
    fi

    if [[ "${COMP_WORDS[COMP_CWORD - 1]}" == "--monitor-newline" ]]; then
        COMPREPLY=($(compgen -W "none lf cr crlf" -- "$cur"))
        return
    fi

    if [[ "${COMP_WORDS[COMP_CWORD - 1]}" == "--monitor-baud" ]]; then
        COMPREPLY=($(compgen -W "115200 230400 460800 921600" -- "$cur"))
        return
    fi

    if [[ "${COMP_WORDS[COMP_CWORD - 1]}" == "--accuracy-input" ]]; then
        compopt -o filenames 2>/dev/null
        COMPREPLY=($(compgen -W "../datasheet/input_all_preprocessed_10000.h datasheet/input_all_preprocessed_10000.h" -- "$cur") $(compgen -f -- "$cur"))
        return
    fi

    if [[ "${COMP_WORDS[COMP_CWORD - 1]}" == "--accuracy-labels" ]]; then
        compopt -o filenames 2>/dev/null
        COMPREPLY=($(compgen -W "../datasheet/label_all_preprocessed_10000.h datasheet/label_all_preprocessed_10000.h" -- "$cur") $(compgen -f -- "$cur"))
        return
    fi

    if [[ "${COMP_WORDS[COMP_CWORD - 1]}" == "--accuracy-count" ]]; then
        COMPREPLY=($(compgen -W "1 10 100 1000 4750 10000" -- "$cur"))
        return
    fi

    if [[ "${COMP_WORDS[COMP_CWORD - 1]}" == "--accuracy-skip" ]]; then
        COMPREPLY=($(compgen -W "0 10 100 1000" -- "$cur"))
        return
    fi

    if [[ "${COMP_WORDS[COMP_CWORD - 1]}" == "--accuracy-input-layout" ]]; then
        COMPREPLY=($(compgen -W "hwc chw" -- "$cur"))
        return
    fi

    if [[ "${COMP_WORDS[COMP_CWORD - 1]}" == "--accuracy-chunk-size" ]]; then
        COMPREPLY=($(compgen -W "32 64 128 256 512 1016" -- "$cur"))
        return
    fi

    if [[ "${COMP_WORDS[COMP_CWORD - 1]}" == "--accuracy-timeout" || "${COMP_WORDS[COMP_CWORD - 1]}" == "--accuracy-run-timeout" ]]; then
        COMPREPLY=($(compgen -W "1.0 3.0 5.0 10.0 30.0" -- "$cur"))
        return
    fi

    if [[ "${COMP_WORDS[COMP_CWORD - 1]}" == "--accuracy-retries" ]]; then
        COMPREPLY=($(compgen -W "0 3 5 10" -- "$cur"))
        return
    fi

    if [[ "${COMP_WORDS[COMP_CWORD - 1]}" == "--accuracy-inter-frame-delay" ]]; then
        COMPREPLY=($(compgen -W "0 0.001 0.002 0.005 0.01" -- "$cur"))
        return
    fi

    if [[ "${COMP_WORDS[COMP_CWORD - 1]}" == "--accuracy-tx-slice-size" ]]; then
        COMPREPLY=($(compgen -W "0 8 16 32 64" -- "$cur"))
        return
    fi

    if [[ "${COMP_WORDS[COMP_CWORD - 1]}" == "--accuracy-tx-slice-delay" ]]; then
        COMPREPLY=($(compgen -W "0 0.0005 0.001 0.002 0.005" -- "$cur"))
        return
    fi

    if [[ "${COMP_WORDS[COMP_CWORD - 1]}" == "--accuracy-progress-every" ]]; then
        COMPREPLY=($(compgen -W "1 10 50 100 500" -- "$cur"))
        return
    fi

    if [[ "${COMP_WORDS[COMP_CWORD - 1]}" == "--accuracy-command" ]]; then
        COMPREPLY=($(compgen -W "4.5" -- "$cur"))
        return
    fi

    if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "$opts" -- "$cur"))
        return
    fi

    local positional_count=0
    local skip_next=0
    local word
    for ((i = 1; i < COMP_CWORD; ++i)); do
        word="${COMP_WORDS[i]}"
        if (( skip_next )); then
            skip_next=0
            continue
        fi
        if [[ "$word" == "--chunk-size" || "$word" == "--boot-timeout" || "$word" == "--write-timeout" || "$word" == "--write-delay" ]]; then
            skip_next=1
            continue
        fi
        if [[ "$word" == "--monitor-timeout" || "$word" == "--monitor-format" || "$word" == "--monitor-input" || "$word" == "--monitor-newline" || "$word" == "--monitor-baud" ]]; then
            skip_next=1
            continue
        fi
        if [[ "$word" == "--accuracy-input" || "$word" == "--accuracy-labels" || "$word" == "--accuracy-count" || "$word" == "--accuracy-skip" || "$word" == "--accuracy-input-layout" || "$word" == "--accuracy-chunk-size" || "$word" == "--accuracy-timeout" || "$word" == "--accuracy-run-timeout" || "$word" == "--accuracy-retries" || "$word" == "--accuracy-inter-frame-delay" || "$word" == "--accuracy-tx-slice-size" || "$word" == "--accuracy-tx-slice-delay" || "$word" == "--accuracy-progress-every" || "$word" == "--accuracy-command" ]]; then
            skip_next=1
            continue
        fi
        [[ "$word" == -* ]] && continue
        ((positional_count++))
    done

    if (( positional_count == 0 )); then
        local old_nullglob
        old_nullglob="$(shopt -p nullglob)"
        shopt -s nullglob
        local ports=(/dev/ttyUSB* /dev/ttyACM* /dev/ttyS*)
        eval "$old_nullglob"

        COMPREPLY=($(compgen -W "$opts ${ports[*]}" -- "$cur"))
        return
    fi

    if (( positional_count == 1 )); then
        compopt -o filenames 2>/dev/null
        COMPREPLY=($(compgen -W "$opts $default_fw" -- "$cur") $(compgen -f -- "$cur"))
        return
    fi
}

_beta_aisoc_uart_weight_sender()
{
    local cur prev opts value_opts
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD - 1]}"
    opts="--port --input --baud --chunk-size --flash-offset --timeout --retries --write-timeout --write-delay --enter-command --interactive-menu --menu-timeout --post-command-timeout --debug --help"
    value_opts="--port --input --baud --chunk-size --flash-offset --timeout --retries --write-timeout --write-delay --enter-command --menu-timeout --post-command-timeout"

    COMPREPLY=()

    case "$prev" in
        --port)
            local old_nullglob
            old_nullglob="$(shopt -p nullglob)"
            shopt -s nullglob
            local ports=(/dev/ttyUSB* /dev/ttyACM* /dev/ttyS*)
            eval "$old_nullglob"

            COMPREPLY=($(compgen -W "/dev/ttyUSB0 /dev/ttyUSB1 /dev/ttyACM0 /dev/ttyACM1 ${ports[*]}" -- "$cur"))
            return
            ;;
        --input)
            compopt -o filenames 2>/dev/null
            COMPREPLY=($(compgen -f -- "$cur"))
            return
            ;;
        --baud)
            COMPREPLY=($(compgen -W "9600 57600 115200 230400 460800 921600" -- "$cur"))
            return
            ;;
        --chunk-size)
            COMPREPLY=($(compgen -W "64 128 256 512 1020" -- "$cur"))
            return
            ;;
        --flash-offset)
            COMPREPLY=($(compgen -W "0x00200000 0x00300000 0x00400000" -- "$cur"))
            return
            ;;
        --timeout|--write-timeout)
            COMPREPLY=($(compgen -W "1.0 2.0 5.0 10.0" -- "$cur"))
            return
            ;;
        --write-delay)
            COMPREPLY=($(compgen -W "0 0.001 0.003 0.005 0.01" -- "$cur"))
            return
            ;;
        --retries)
            COMPREPLY=($(compgen -W "5 10 20 30" -- "$cur"))
            return
            ;;
        --enter-command)
            COMPREPLY=($(compgen -W "2.1" -- "$cur"))
            return
            ;;
        --menu-timeout|--post-command-timeout)
            COMPREPLY=($(compgen -W "0 0.2 0.3 1.0 3.0 5.0" -- "$cur"))
            return
            ;;
    esac

    if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "$opts" -- "$cur"))
        return
    fi

    local skip_next=0
    local has_input=0
    local word
    for ((i = 1; i < COMP_CWORD; ++i)); do
        word="${COMP_WORDS[i]}"
        if (( skip_next )); then
            skip_next=0
            continue
        fi
        if [[ " $value_opts " == *" $word "* ]]; then
            [[ "$word" == "--input" ]] && has_input=1
            skip_next=1
            continue
        fi
    done

    if (( ! has_input )); then
        compopt -o filenames 2>/dev/null
        COMPREPLY=($(compgen -W "$opts Build/allcnnc_160_packed_weights.hex Build/allcnn_cifar10_weights.hex Build/weights.hex Build/s27kl0641.mem Build/s27kl0641_from_feature.mem Build/weights_from_feature.mem" -- "$cur") $(compgen -f -- "$cur"))
        return
    fi

    COMPREPLY=($(compgen -W "$opts" -- "$cur"))
}

_beta_aisoc_capture_dataset()
{
    local cur prev opts value_opts labels
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD - 1]}"
    opts="--device --label --out --count --interval --warmup --width --height --no-preview --show-32 --fullscreen --preview-scale --person-target --help"
    value_opts="--device --label --out --count --interval --warmup --width --height --preview-scale --person-target"
    labels="paper rock scissors"

    COMPREPLY=()

    case "$prev" in
        --device)
            local old_nullglob
            old_nullglob="$(shopt -p nullglob)"
            shopt -s nullglob
            local video_devs=(/dev/video*)
            eval "$old_nullglob"

            COMPREPLY=($(compgen -W "0 1 2 3 4 5 ${video_devs[*]}" -- "$cur"))
            return
            ;;
        --label)
            COMPREPLY=($(compgen -W "$labels" -- "$cur"))
            return
            ;;
        --out)
            compopt -o filenames 2>/dev/null
            COMPREPLY=($(compgen -W "dataset_capture/raw dataset_capture/train dataset_capture/val" -- "$cur") $(compgen -d -- "$cur"))
            return
            ;;
        --count)
            COMPREPLY=($(compgen -W "0 50 100 200 500 1000" -- "$cur"))
            return
            ;;
        --interval)
            COMPREPLY=($(compgen -W "0 0.1 0.2 0.5 1.0" -- "$cur"))
            return
            ;;
        --warmup)
            COMPREPLY=($(compgen -W "0 1.0 2.0 3.0 5.0" -- "$cur"))
            return
            ;;
        --width)
            COMPREPLY=($(compgen -W "640 1280 1920" -- "$cur"))
            return
            ;;
        --height)
            COMPREPLY=($(compgen -W "480 720 1080" -- "$cur"))
            return
            ;;
        --preview-scale)
            COMPREPLY=($(compgen -W "0.5 0.75 1.0 1.25 1.5" -- "$cur"))
            return
            ;;
        --person-target)
            COMPREPLY=($(compgen -W "10 20 30 50 100" -- "$cur"))
            return
            ;;
    esac

    if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "$opts" -- "$cur"))
        return
    fi

    local skip_next=0
    local word
    for ((i = 1; i < COMP_CWORD; ++i)); do
        word="${COMP_WORDS[i]}"
        if (( skip_next )); then
            skip_next=0
            continue
        fi
        if [[ " $value_opts " == *" $word "* ]]; then
            skip_next=1
            continue
        fi
    done

    COMPREPLY=($(compgen -W "$opts" -- "$cur"))
}

_beta_aisoc_golden_model_main()
{
    local cur prev opts
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD - 1]}"
    opts="--device --width --height --warmup --backend --model --fp32-model --all-cnn-c-160-model --all-cnn-c-160-stats --alexnet-model --squeezenet-model --uart-port --uart-baud --uart-newline --window-width --window-height --fullscreen --resize-mode --help"

    COMPREPLY=()

    case "$prev" in
        --device)
            local old_nullglob
            old_nullglob="$(shopt -p nullglob)"
            shopt -s nullglob
            local video_devs=(/dev/video*)
            eval "$old_nullglob"

            COMPREPLY=($(compgen -W "0 1 2 3 4 5 ${video_devs[*]}" -- "$cur"))
            return
            ;;
        --width)
            COMPREPLY=($(compgen -W "640 1280 1920" -- "$cur"))
            return
            ;;
        --height)
            COMPREPLY=($(compgen -W "480 720 1080" -- "$cur"))
            return
            ;;
        --warmup)
            COMPREPLY=($(compgen -W "0 0.5 1.0 2.0" -- "$cur"))
            return
            ;;
        --backend)
            COMPREPLY=($(compgen -W "all_cnn_c_160 tflite tflite-int8 tflite-fp32 fp32 alexnet alexnet-int8 squeezenet1_1" -- "$cur"))
            return
            ;;
        --model)
            compopt -o filenames 2>/dev/null
            COMPREPLY=($(compgen -W "./models/ALL_CNN_C_INT8_per_tensor.tflite" -- "$cur") $(compgen -f -- "$cur"))
            return
            ;;
        --fp32-model)
            compopt -o filenames 2>/dev/null
            COMPREPLY=($(compgen -W "./models/ALL_CNN_C_FLOAT32.tflite" -- "$cur") $(compgen -f -- "$cur"))
            return
            ;;
        --all-cnn-c-160-model)
            compopt -o filenames 2>/dev/null
            COMPREPLY=($(compgen -W "./models/all_cnn_c_160_rps_float32.tflite ./models/all_cnn_c_160_rps_int8_per_layer.tflite" -- "$cur") $(compgen -f -- "$cur"))
            return
            ;;
        --all-cnn-c-160-stats)
            compopt -o filenames 2>/dev/null
            COMPREPLY=($(compgen -W "./models/all_cnn_c_160_rps_stats.json ./models/all_cnn_c_160_rps_fixed_params_per_layer.json" -- "$cur") $(compgen -f -- "$cur"))
            return
            ;;
        --alexnet-model|--squeezenet-model)
            compopt -o filenames 2>/dev/null
            COMPREPLY=($(compgen -f -- "$cur"))
            return
            ;;
        --uart-port)
            local old_nullglob
            old_nullglob="$(shopt -p nullglob)"
            shopt -s nullglob
            local ports=(/dev/ttyUSB* /dev/ttyACM* /dev/ttyS*)
            eval "$old_nullglob"

            COMPREPLY=($(compgen -W "/dev/ttyUSB0 /dev/ttyUSB1 /dev/ttyACM0 /dev/ttyACM1 ${ports[*]}" -- "$cur"))
            return
            ;;
        --uart-baud)
            COMPREPLY=($(compgen -W "9600 57600 115200 230400 460800 921600" -- "$cur"))
            return
            ;;
        --uart-newline)
            COMPREPLY=($(compgen -W "none lf cr crlf" -- "$cur"))
            return
            ;;
        --window-width)
            COMPREPLY=($(compgen -W "1280 1600 1920" -- "$cur"))
            return
            ;;
        --window-height)
            COMPREPLY=($(compgen -W "720 900 1080" -- "$cur"))
            return
            ;;
        --resize-mode)
            COMPREPLY=($(compgen -W "pad_max_pool pad_avg_pool avg_pool resize resize_bilinear resize_bicubic crop_resize crop_avg_pool crop_max_pool" -- "$cur"))
            return
            ;;
    esac

    COMPREPLY=($(compgen -W "$opts" -- "$cur"))
}

_beta_aisoc_python_dispatch()
{
    local script_index=-1
    local word
    local i

    for ((i = 1; i < ${#COMP_WORDS[@]}; ++i)); do
        word="${COMP_WORDS[i]}"
        case "$word" in
            src/main.py|./src/main.py|*/software_golden_model_rps/src/main.py)
                script_index="$i"
                break
                ;;
        esac
    done

    if (( script_index < 0 )); then
        return 1
    fi

    _beta_aisoc_golden_model_main
}

complete -F _beta_aisoc_builder builder.py
complete -F _beta_aisoc_builder scripts/builder.py
complete -F _beta_aisoc_builder ./scripts/builder.py

complete -F _beta_aisoc_host_flasher host_flasher.py
complete -F _beta_aisoc_host_flasher scripts/host_flasher.py
complete -F _beta_aisoc_host_flasher ./scripts/host_flasher.py

complete -F _beta_aisoc_uart_weight_sender uart_weight_sender.py
complete -F _beta_aisoc_uart_weight_sender scripts/uart_weight_sender.py
complete -F _beta_aisoc_uart_weight_sender ./scripts/uart_weight_sender.py

complete -F _beta_aisoc_capture_dataset capture_dataset.py
complete -F _beta_aisoc_capture_dataset scripts/capture_dataset.py
complete -F _beta_aisoc_capture_dataset ./scripts/capture_dataset.py

complete -o default -o bashdefault -F _beta_aisoc_python_dispatch python
complete -o default -o bashdefault -F _beta_aisoc_python_dispatch python3
