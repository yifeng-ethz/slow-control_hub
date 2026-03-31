# ============================================================================
# sc_hub_v2 "Slow Control Hub v2" v26.3.0
# Yifeng Wang 2026.03.31
#
# Comprehensive _hw.tcl for sc_hub_v2 with:
#   - Preset-based configuration (JESD204B GUI style)
#   - Dynamic GUI elaboration per feature set
#   - TLM result integration for performance preview
#   - Resource estimation from synthesis database
#   - Modular sub-files for maintainability
#
# Sub-file organization:
#   hw_tcl/sc_hub_v2_params.tcl      Parameter definitions and defaults
#   hw_tcl/sc_hub_v2_presets.tcl     Preset matrix (perf x area x features)
#   hw_tcl/sc_hub_v2_gui.tcl        GUI tabs, dynamic elaboration
#   hw_tcl/sc_hub_v2_validate.tcl   Parameter range and cross-validation
#   hw_tcl/sc_hub_v2_connections.tcl Interface and HDL file composition
#   hw_tcl/sc_hub_v2_tlm_preview.tcl TLM CSV lookup and performance preview
#   hw_tcl/sc_hub_v2_report.tcl     Resource estimation and reporting
#
# GUI modeled after the Intel JESD204B IP and Mu3e IP wrappers.
# ============================================================================

package require -exact qsys 16.1

# ----------------------------------------------------------------------------
# Module properties
# ----------------------------------------------------------------------------

set_module_property NAME                    sc_hub_v2
set_module_property DISPLAY_NAME            "Slow Control Hub v2"
set_module_property VERSION                 26.3.0
set_module_property DESCRIPTION             \
    "Modular slow-control hub with split-buffer architecture, linked-list \
     payload RAM, out-of-order dispatch, atomic RMW, release/acquire ordering \
     semantics, and selectable Avalon-MM / AXI4 master interface. \
     Configurable via presets or manual parameter tuning."
set_module_property GROUP                   "Mu3e Control Plane/Modules"
set_module_property AUTHOR                  "Yifeng Wang"
set_module_property INTERNAL                false
set_module_property OPAQUE_ADDRESS_MAP      true
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property EDITABLE                true
set_module_property REPORT_TO_TALKBACK      false
set_module_property ALLOW_GREYBOX_GENERATION false
set_module_property REPORT_HIERARCHY        false
set_module_property ICON_PATH               ../figures/mu3e_logo.png

# Callbacks — routed to sub-file procs
set_module_property ELABORATION_CALLBACK    sc_hub_v2_elaborate
set_module_property VALIDATION_CALLBACK     sc_hub_v2_validate

# ----------------------------------------------------------------------------
# Resolve sub-file paths relative to this script
# ----------------------------------------------------------------------------
#
# qsys-generate can evaluate this component from the catalog root instead of the
# component directory. Fall back to the slow-control_hub subdir in that case so
# the modular hw_tcl/ split still resolves deterministically.
set SCRIPT_DIR [file dirname [file normalize [info script]]]
set ::sc_hub_v2_component_dir $SCRIPT_DIR
set HW_TCL_DIR [file join $::sc_hub_v2_component_dir hw_tcl]

if {![file isdirectory $HW_TCL_DIR]} {
    set alt_component_dir [file join $SCRIPT_DIR slow-control_hub]
    set alt_hw_tcl_dir [file join $alt_component_dir hw_tcl]
    if {[file isdirectory $alt_hw_tcl_dir]} {
        set ::sc_hub_v2_component_dir $alt_component_dir
        set HW_TCL_DIR $alt_hw_tcl_dir
    } else {
        error "sc_hub_v2_hw.tcl: could not locate hw_tcl/ under $SCRIPT_DIR or $alt_component_dir"
    }
}

# ----------------------------------------------------------------------------
# Source sub-files in dependency order
# ----------------------------------------------------------------------------

# 1. Utility procs (HTML helpers, common accessors)
source [file join $HW_TCL_DIR sc_hub_v2_utils.tcl]

# 2. Parameter definitions — must come before GUI and presets
source [file join $HW_TCL_DIR sc_hub_v2_params.tcl]

# 3. Preset matrix — defines named configurations
source [file join $HW_TCL_DIR sc_hub_v2_presets.tcl]

# 4. GUI layout — tabs, display items, dynamic visibility
source [file join $HW_TCL_DIR sc_hub_v2_gui.tcl]

# 5. Validation logic — parameter range and cross-checks
source [file join $HW_TCL_DIR sc_hub_v2_validate.tcl]

# 6. TLM performance preview — CSV lookup and HTML generation
source [file join $HW_TCL_DIR sc_hub_v2_tlm_preview.tcl]

# 7. Resource estimation — ALM/M10K/M20K from synthesis database
source [file join $HW_TCL_DIR sc_hub_v2_report.tcl]

# 8. Interface and HDL file composition — last, depends on params
source [file join $HW_TCL_DIR sc_hub_v2_connections.tcl]
sc_hub_v2_init_fileset

# ----------------------------------------------------------------------------
# Top-level elaboration callback
# ----------------------------------------------------------------------------
proc sc_hub_v2_elaborate {} {
    # 1. Apply preset if user selected one (overrides individual params)
    sc_hub_v2_apply_preset_if_changed

    # 2. Build interfaces based on current parameter values
    sc_hub_v2_build_interfaces

    # 3. Build fileset based on enabled features
    sc_hub_v2_build_fileset

    # 4. Update GUI dynamic sections
    sc_hub_v2_update_gui

    # 5. Generate TLM performance preview HTML
    sc_hub_v2_update_tlm_preview

    # 6. Generate resource estimation
    sc_hub_v2_update_resource_estimate

    # 7. Generate BDF performance plot reference
    sc_hub_v2_update_perf_plot
}

# Alias for Platform Designer
proc elaborate {} {
    sc_hub_v2_elaborate
}

# ----------------------------------------------------------------------------
# Top-level validation callback
# ----------------------------------------------------------------------------
proc sc_hub_v2_validate {} {
    # 1. Parameter range checks
    sc_hub_v2_validate_ranges

    # 2. Cross-parameter consistency
    sc_hub_v2_validate_cross

    # 3. Feature dependency checks
    sc_hub_v2_validate_features

    # 4. Warn on risky configurations
    sc_hub_v2_validate_warnings
}

proc validate {} {
    sc_hub_v2_validate
}
