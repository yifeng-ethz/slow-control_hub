# ============================================================================
# sc_hub_v2 — Utility procedures
# ============================================================================

# Insert styled HTML text into a GUI group
proc sc_hub_v2_add_html {group_name item_name html_text} {
    add_display_item $group_name $item_name TEXT ""
    set_display_item_property $item_name DISPLAY_HINT html
    set_display_item_property $item_name TEXT $html_text
}

# Conditional parameter visibility
proc sc_hub_v2_show_param {param_name visible} {
    set_parameter_property $param_name VISIBLE $visible
}

# Conditional display item visibility
proc sc_hub_v2_show_item {item_name visible} {
    catch {set_display_item_property $item_name VISIBLE $visible}
}

# Safe parameter read with default
proc sc_hub_v2_get_param {name {default_val ""}} {
    if {[catch {set val [get_parameter_value $name]}]} {
        return $default_val
    }
    return $val
}

# Format an integer with commas for display
proc sc_hub_v2_format_int {n} {
    set s [format "%d" $n]
    set len [string length $s]
    set result ""
    for {set i 0} {$i < $len} {incr i} {
        if {$i > 0 && ($len - $i) % 3 == 0} {
            append result ","
        }
        append result [string index $s $i]
    }
    return $result
}

# Build an HTML table from a list of {header_list row_list_of_lists}
proc sc_hub_v2_html_table {headers rows {width "100%"}} {
    set html "<table border=\"1\" cellpadding=\"4\" width=\"$width\">\n<tr>"
    foreach h $headers {
        append html "<th>$h</th>"
    }
    append html "</tr>\n"
    foreach row $rows {
        append html "<tr>"
        foreach cell $row {
            append html "<td>$cell</td>"
        }
        append html "</tr>\n"
    }
    append html "</table>"
    return $html
}

# Compute ceil(log2(n)), minimum 1
proc sc_hub_v2_clog2 {n} {
    if {$n <= 1} {return 1}
    set bits 0
    set val [expr {$n - 1}]
    while {$val > 0} {
        set val [expr {$val >> 1}]
        incr bits
    }
    return $bits
}

# Check if a value is a power of 2
proc sc_hub_v2_is_pow2 {n} {
    if {$n <= 0} {return 0}
    return [expr {($n & ($n - 1)) == 0}]
}
