set_param general.maxThreads 1
set_param synth.maxThreads 1
puts "BBHT serial synthesis: general=[get_param general.maxThreads] synth=[get_param synth.maxThreads]"
synth_design
