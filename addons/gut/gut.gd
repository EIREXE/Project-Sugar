################################################################################
#(G)odot (U)nit (T)est class
#
################################################################################
#The MIT License (MIT)
#=====================
#
#Copyright (c) 2019 Tom "Butch" Wesley
#
#Permission is hereby granted, free of charge, to any person obtaining a copy
#of this software and associated documentation files (the "Software"), to deal
#in the Software without restriction, including without limitation the rights
#to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#copies of the Software, and to permit persons to whom the Software is
#furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in
#all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
#THE SOFTWARE.
#
################################################################################
# View readme for usage details.
#
# Version 6.6.2
################################################################################
extends "res://addons/gut/gut_gui.gd"

var _utils = load('res://addons/gut/utils.gd').new()
var _lgr = _utils.get_logger()
var _deprecated_tracker = _utils.ThingCounter.new()

# ###########################
# Editor Variables
# ###########################
export var _should_maximize = false setget set_should_maximize, get_should_maximize
export var _run_on_load = false
export(String) var _select_script = null
export(String) var _tests_like = null
export(String) var _inner_class_name = null
export var _should_print_to_console = true setget set_should_print_to_console, get_should_print_to_console
export(int, 'Failures only', 'Tests and failures', 'Everything') var _log_level = 1 setget set_log_level, get_log_level
# This var is JUST used to expose this setting in the editor
# the var that is used is in the _yield_between hash.
export var _yield_between_tests = true setget set_yield_between_tests, get_yield_between_tests
export var _disable_strict_datatype_checks = false setget disable_strict_datatype_checks, is_strict_datatype_checks_disabled
# The prefix used to get tests.
export var _test_prefix = 'test_'
export var _file_prefix = 'test_'
export var _file_extension = '.gd'
export var _inner_class_prefix = 'Test'
export(String) var _temp_directory = 'user://gut_temp_directory'
export var _include_subdirectories = false setget set_include_subdirectories, get_include_subdirectories
export(int, 'FULL', 'PARTIAL') var _double_strategy = _utils.DOUBLE_STRATEGY.PARTIAL setget set_double_strategy, get_double_strategy

# Allow user to add test directories via editor.  This is done with strings
# instead of an array because the interface for editing arrays is really
# cumbersome and complicates testing because arrays set through the editor
# apply to ALL instances.  This also allows the user to use the built in
# dialog to pick a directory.
export(String, DIR) var _directory1 = ''
export(String, DIR) var _directory2 = ''
export(String, DIR) var _directory3 = ''
export(String, DIR) var _directory4 = ''
export(String, DIR) var _directory5 = ''
export(String, DIR) var _directory6 = ''


# ###########################
# Other Vars
# ###########################
const LOG_LEVEL_FAIL_ONLY = 0
const LOG_LEVEL_TEST_AND_FAILURES = 1
const LOG_LEVEL_ALL_ASSERTS = 2
const WAITING_MESSAGE = '/# waiting #/'
const PAUSE_MESSAGE = '/# Pausing.  Press continue button...#/'

var _stop_pressed = false
var _test_collector = load('res://addons/gut/test_collector.gd').new()

# The instanced scripts.  This is populated as the scripts are run.
var _test_script_objects = []

var _waiting = false
var _done = false

var _current_test = null
var _log_text = ""

var _pause_before_teardown = false
# when true _pause_before_teardown will be ignored.  useful
# when batch processing and you don't want to watch.
var _ignore_pause_before_teardown = false
var _wait_timer = Timer.new()

var _yield_between = {
	should = false,
	timer = Timer.new(),
	after_x_tests = 5,
	tests_since_last_yield = 0
}

var _was_yield_method_called = false
# used when yielding to gut instead of some other
# signal.  Start with set_yield_time()
var _yield_timer = Timer.new()
var _runtime_timer = Timer.new()
const RUNTIME_START_TIME = float(20000.0)

var _unit_test_name = ''
var Summary = load('res://addons/gut/summary.gd')
var _new_summary = null

var _yielding_to = {
	obj = null,
	signal_name = ''
}

var _stubber = _utils.Stubber.new()
var _doubler = _utils.Doubler.new()
var _spy = _utils.Spy.new()

const SIGNAL_TESTS_FINISHED = 'tests_finished'
const SIGNAL_STOP_YIELD_BEFORE_TEARDOWN = 'stop_yield_before_teardown'

# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
func _init():
	add_user_signal(SIGNAL_TESTS_FINISHED)
	add_user_signal(SIGNAL_STOP_YIELD_BEFORE_TEARDOWN)
	add_user_signal('timeout')
	add_user_signal('done_waiting')
	_doubler.set_output_dir(_temp_directory)
	_doubler.set_stubber(_stubber)
	_doubler.set_spy(_spy)
	_doubler.set_logger(_lgr)
	_lgr.set_gut(self)

	_stubber.set_logger(_lgr)
	_test_collector.set_logger(_lgr)

# ------------------------------------------------------------------------------
# Connect all the controls created in the parent class to the methods here.
# ------------------------------------------------------------------------------
func _connect_controls():
	_ctrls.copy_button.connect("pressed", self, "_copy_button_pressed")
	_ctrls.clear_button.connect("pressed", self, "clear_text")
	_ctrls.continue_button.connect("pressed", self, "_on_continue_button_pressed")
	_ctrls.ignore_continue_checkbox.connect('pressed', self, '_on_ignore_continue_checkbox_pressed')
	_ctrls.log_level_slider.connect("value_changed", self, "_on_log_level_slider_changed")
	_ctrls.stop_button.connect("pressed", self, '_on_stop_button_pressed')
	_ctrls.run_rest.connect('pressed', self, '_on_run_rest_pressed')
	_ctrls.previous_button.connect("pressed", self, '_on_previous_button_pressed')
	_ctrls.next_button.connect("pressed", self, '_on_next_button_pressed')
	_ctrls.scripts_drop_down.connect('item_selected', self, '_on_script_selected')
	_ctrls.run_button.connect("pressed", self, "_on_run_button_pressed")

# ------------------------------------------------------------------------------
# Initialize controls
# ------------------------------------------------------------------------------
func _ready():
	_lgr.info(str('using [', OS.get_user_data_dir(), '] for temporary output.'))

	set_it_up()
	set_process_input(true)
	_connect_controls()
	set_position(get_position() + title_offset)

	add_child(_wait_timer)
	_wait_timer.set_wait_time(1)
	_wait_timer.set_one_shot(true)

	add_child(_yield_between.timer)
	_wait_timer.set_one_shot(true)

	add_child(_yield_timer)
	_yield_timer.set_one_shot(true)
	_yield_timer.connect('timeout', self, '_yielding_callback')

	# This timer is started, but it should never finish.  Used
	# to determine how long it took to run the tests since
	# getting the time and doing time math is ridiculous in godot.
	add_child(_runtime_timer)
	_runtime_timer.set_one_shot(true)
	_runtime_timer.set_wait_time(RUNTIME_START_TIME)

	add_directory(_directory1)
	add_directory(_directory2)
	add_directory(_directory3)
	add_directory(_directory4)
	add_directory(_directory5)
	add_directory(_directory6)

	if(_select_script != null):
		select_script(_select_script)

	if(_tests_like != null):
		set_unit_test_name(_tests_like)

	if(_run_on_load):
		test_scripts(_select_script == null)

	if(_should_maximize):
		maximize()

	show()

#####################
#
# Events
#
#####################

# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
func _process(delta):
	if(_is_running):
		_ctrls.runtime_label.set_text(str(RUNTIME_START_TIME - _runtime_timer.get_time_left()).pad_decimals(3) + ' s')

# ------------------------------------------------------------------------------
# Timeout for the built in timer.  emits the timeout signal.  Start timer
# with set_yield_time()
# ------------------------------------------------------------------------------
func _yielding_callback(from_obj=false):
	if(_yielding_to.obj):
		_yielding_to.obj.disconnect(_yielding_to.signal_name, self, '_yielding_callback')
		_yielding_to.obj = null
		_yielding_to.signal_name = ''

	if(from_obj):
		# we must yiled for a little longer after the signal is emitted so that
		# the signal can propigate to other objects.  This was discovered trying
		# to assert that obj/signal_name was emitted.  Without this extra delay
		# the yield returns and processing finishes before the rest of the
		# objects can get the signal.  This works b/c the timer will timeout
		# and come back into this method but from_obj will be false.
		_yield_timer.set_wait_time(.1)
		_yield_timer.start()
	else:
		emit_signal('timeout')

# ------------------------------------------------------------------------------
# Run either the selected test or all tests.
# ------------------------------------------------------------------------------
func _on_run_button_pressed():
	test_scripts()

# ------------------------------------------------------------------------------
# Continue processing after pause.
# ------------------------------------------------------------------------------
func _on_continue_button_pressed():
	_pause_before_teardown = false
	_ctrls.continue_button.set_disabled(true)
	emit_signal(SIGNAL_STOP_YIELD_BEFORE_TEARDOWN)

# ------------------------------------------------------------------------------
# Change the log level.  Will be visible the next time tests are run.
# ------------------------------------------------------------------------------
func _on_log_level_slider_changed(value):
	_log_level = _ctrls.log_level_slider.get_value()

# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
func _on_previous_button_pressed():
	if(_ctrls.scripts_drop_down.get_selected() > 0):
		_ctrls.scripts_drop_down.select(_ctrls.scripts_drop_down.get_selected() -1)
	_update_controls()

# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
func _on_next_button_pressed():
	if(_ctrls.scripts_drop_down.get_selected() < _ctrls.scripts_drop_down.get_item_count() -1):
		_ctrls.scripts_drop_down.select(_ctrls.scripts_drop_down.get_selected() +1)
	_update_controls()

# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
func _on_stop_button_pressed():
	_stop_pressed = true
	_ctrls.stop_button.set_disabled(true)
	# short circuit any yielding or yielded tests
	if(!_ctrls.continue_button.is_disabled()):
		_on_continue_button_pressed()
	else:
		_waiting = false

# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
func _on_ignore_continue_checkbox_pressed():
	_ignore_pause_before_teardown = _ctrls.ignore_continue_checkbox.is_pressed()
	# If you want to ignore them, then you probably just want to continue
	# running, so we'll save you a click.
	if(!_ctrls.continue_button.is_disabled()):
		_on_continue_button_pressed()

# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
func _on_script_selected(id):
	_update_controls()

# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
func _on_run_rest_pressed():
	test_scripts(true)

# ------------------------------------------------------------------------------
# completed signal for GDScriptFucntionState returned from a test script that
# has yielded
# ------------------------------------------------------------------------------
func _on_test_script_yield_completed():
	_waiting = false

#####################
#
# Private
#
#####################

# ------------------------------------------------------------------------------
# Convert the _summary dictionary into text
# ------------------------------------------------------------------------------
func _get_summary_text():
	var to_return = "\n\n*****************\nRun Summary\n*****************"

	to_return += "\n" + _new_summary.get_summary_text() + "\n"

	var logger_text = ''
	if(_lgr.get_errors().size() > 0):
		logger_text += str("\n  * ", _lgr.get_errors().size(), ' Errors.')
	if(_lgr.get_warnings().size() > 0):
		logger_text += str("\n  * ", _lgr.get_warnings().size(), ' Warnings.')
	if(_lgr.get_deprecated().size() > 0):
		logger_text += str("\n  * ", _lgr.get_deprecated().size(), ' Deprecated calls.')
	if(logger_text != ''):
		logger_text = "\nWarnings/Errors:" + logger_text + "\n\n"
	to_return += logger_text

	if(_new_summary.get_totals().tests > 0):
		to_return +=  '+++ ' + str(_new_summary.get_totals().passing) + ' passed ' + str(_new_summary.get_totals().failing) + ' failed.  ' + \
		              "Tests finished in:  " + _ctrls.runtime_label.get_text() + ' +++'
		var c = Color(0, 1, 0)
		if(_new_summary.get_totals().failing > 0):
			c = Color(1, 0, 0)
		elif(_new_summary.get_totals().pending > 0):
			c = Color(1, 1, .8)

		_ctrls.text_box.add_color_region('+++', '+++', c)
	else:
		to_return += '+++ No tests ran +++'
		_ctrls.text_box.add_color_region('+++', '+++', Color(1, 0, 0))

	if(_summary.moved_methods > 0):
		to_return += "\nMoved Methods (" + str(_summary.moved_methods) + ')' + """
-------------
It looks like you have some methods that have been moved.  These methods were
moved from the gut object to the test object so that you don't have to prefix
them with 'gut.'.  This means less typing for you and better organization of
the code.  I'm sorry for the inconvenience but I promise this will make things
easier in the future...I'm pretty sure at least.  Thanks for using Gut!"""

	return to_return + "\n\n"

# ------------------------------------------------------------------------------
# Initialize variables for each run of a single test script.
# ------------------------------------------------------------------------------
func _init_run():
	_test_collector.set_test_class_prefix(_inner_class_prefix)
	_test_script_objects = []
	_new_summary = Summary.new()
	_summary.tally_passed = 0
	_summary.tally_failed = 0

	_log_text = ""

	_current_test = null

	_is_running = true
	_update_controls()

	_runtime_timer.start()

	_yield_between.tests_since_last_yield = 0
	._init_run()
	_ctrls.script_progress.set_max(_test_collector.scripts.size())
	_ctrls.script_progress.set_value(0)

# ------------------------------------------------------------------------------
# Print out run information and close out the run.
# ------------------------------------------------------------------------------
func _end_run():
	var failed_tests = []
	var more_than_one = _test_script_objects.size() > 1

	p(_get_summary_text(), 0)

	# For some reason the text edit control isn't scrolling to the bottom after
	# the summary is printed.  As a workaround, yield for a short time and
	# then move the cursor.  I found this workaround through trial and error.
	_yield_between.timer.set_wait_time(0.001)
	_yield_between.timer.start()
	yield(_yield_between.timer, 'timeout')
	_ctrls.text_box.cursor_set_line(_ctrls.text_box.get_line_count())

	_runtime_timer.stop()
	_is_running = false
	update()
	_update_controls()
	emit_signal(SIGNAL_TESTS_FINISHED)
	set_title("Finished.  " + str(get_fail_count()) + " failures.")

# ------------------------------------------------------------------------------
# Checks the passed in thing to see if it is a "function state" object that gets
# returned when a function yields.
# ------------------------------------------------------------------------------
func _is_function_state(script_result):
	return script_result != null and \
	       typeof(script_result) == TYPE_OBJECT and \
	       script_result is GDScriptFunctionState

# ------------------------------------------------------------------------------
# Print out the heading for a new script
# ------------------------------------------------------------------------------
func _print_script_heading(script):
	if(_does_class_name_match(_inner_class_name, script.class_name)):
		p("\n/-----------------------------------------")
		if(script.class_name == null):
			p("Running Script " + script.path, 0)
		else:
			p("Running Class [" + script.class_name + "] in " + script.path, 0)

		if(_inner_class_name != null and _does_class_name_match(_inner_class_name, script.class_name)):
			p(str('  [',script.class_name, '] matches [', _inner_class_name, ']'))

		if(_unit_test_name != ''):
			p('  Only running tests like: "' + _unit_test_name + '"')

		p("-----------------------------------------/")

# ------------------------------------------------------------------------------
# Just gets more logic out of _test_the_scripts.  Decides if we should yield after
# this test based on flags and counters.
# ------------------------------------------------------------------------------
func _should_yield_now():
	var should = _yield_between.should and \
	             _yield_between.tests_since_last_yield == _yield_between.after_x_tests
	if(should):
		_yield_between.tests_since_last_yield = 0
	else:
		_yield_between.tests_since_last_yield += 1
	return should

# ------------------------------------------------------------------------------
# Yes if the class name is null or the script's class name includes class_name
# ------------------------------------------------------------------------------
func _does_class_name_match(class_name, script_class_name):
	return class_name == null or (script_class_name != null and script_class_name.find(class_name) != -1)

# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
func _setup_script(test_script):
	test_script.gut = self
	test_script.set_logger(_lgr)
	add_child(test_script)
	_test_script_objects.append(test_script)


# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
func _do_yield_between(time):
	_yield_between.timer.set_wait_time(time)
	_yield_between.timer.start()
	return _yield_between.timer

# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
func _wait_for_done(result):
	var iter_counter = 0
	var print_after = 3

	# sets waiting to false.
	result.connect('completed', self, '_on_test_script_yield_completed')

	if(!_was_yield_method_called):
		p('/# Yield detected, waiting #/')

	_was_yield_method_called = false
	_waiting = true
	_wait_timer.set_wait_time(0.25)

	while(_waiting):
		iter_counter += 1
		if(iter_counter > print_after):
			p(WAITING_MESSAGE, 2)
			iter_counter = 0
		_wait_timer.start()
		yield(_wait_timer, 'timeout')

	emit_signal('done_waiting')

# ------------------------------------------------------------------------------
# returns self so it can be integrated into the yield call.
# ------------------------------------------------------------------------------
func _wait_for_continue_button():
	p(PAUSE_MESSAGE, 0)
	_waiting = true
	_ctrls.continue_button.set_disabled(false)
	return self

# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
func _call_deprecated_script_method(script, method, alt):
	if(script.has_method(method)):
		var txt = str(script, '-', method)
		if(!_deprecated_tracker.has(txt)):
			_lgr.deprecated(str('The method ', method, ' has been deprecated, use ', alt, ' instead.'))
			_deprecated_tracker.add(txt)
		script.call(method)

# ------------------------------------------------------------------------------
# Run all tests in a script.  This is the core logic for running tests.
#
# Note, this has to stay as a giant monstrosity of a method because of the
# yields.
# ------------------------------------------------------------------------------
func _test_the_scripts():
	_init_run()
	var file = File.new()
	if(_doubler.get_strategy() == _utils.DOUBLE_STRATEGY.FULL):
		_lgr.info("Using Double Strategy FULL as default strategy.  Keep an eye out for weirdness, this is still experimental.")

	# loop through scripts
	for s in range(_test_collector.scripts.size()):
		var the_script = _test_collector.scripts[s]

		if(the_script.tests.size() > 0):
			set_title('Running:  ' + the_script.get_full_name())
			_print_script_heading(the_script)
			_new_summary.add_script(the_script.get_full_name())

		var test_script = the_script.get_new()
		var script_result = null
		_setup_script(test_script)
		_doubler.set_strategy(_double_strategy)

		# yield between test scripts so things paint
		if(_yield_between.should):
			yield(_do_yield_between(0.01), 'timeout')

		# !!!
		# Hack so there isn't another indent to this monster of a method.  if
		# inner class is set and we do not have a match then empty the tests
		# for the current test.
		# !!!
		if(!_does_class_name_match(_inner_class_name, the_script.class_name)):
			the_script.tests = []
		else:
			# call both pre-all-tests methods until prerun_setup is removed
			_call_deprecated_script_method(test_script, 'prerun_setup', 'before_all')
			test_script.before_all()

		_ctrls.test_progress.set_max(the_script.tests.size())

		# Each test in the script
		for i in range(the_script.tests.size()):
			_stubber.clear()
			_spy.clear()
			_doubler.clear_output_directory()
			_current_test = the_script.tests[i]

			if((_unit_test_name != '' and _current_test.name.find(_unit_test_name) > -1) or
			   (_unit_test_name == '')):
				p(_current_test.name, 1)
				_new_summary.add_test(_current_test.name)

				# yield so things paint
				if(_should_yield_now()):
					yield(_do_yield_between(0.001), 'timeout')

				_call_deprecated_script_method(test_script, 'setup', 'before_each')
				test_script.before_each()


				#When the script yields it will return a GDScriptFunctionState object
				script_result = test_script.call(_current_test.name)
				if(_is_function_state(script_result)):
					_wait_for_done(script_result)
					yield(self, 'done_waiting')


				#if the test called pause_before_teardown then yield until
				#the continue button is pressed.
				if(_pause_before_teardown and !_ignore_pause_before_teardown):
					yield(_wait_for_continue_button(), SIGNAL_STOP_YIELD_BEFORE_TEARDOWN)

				test_script.clear_signal_watcher()

				# call each post-each-test method until teardown is removed.
				_call_deprecated_script_method(test_script, 'teardown', 'after_each')
				test_script.after_each()

				if(_current_test.passed):
					_ctrls.text_box.add_keyword_color(_current_test.name, Color(0, 1, 0))
				else:
					_ctrls.text_box.add_keyword_color(_current_test.name, Color(1, 0, 0))

				# !!! STOP BUTTON SHORT CIRCUIT !!!
				if(_stop_pressed):
					_is_running = false
					_update_controls()
					_stop_pressed = false
					p("STOPPED")
					return

				_ctrls.test_progress.set_value(i + 1)

		# call both post-all-tests methods until postrun_teardown is removed.
		if(_does_class_name_match(_inner_class_name, the_script.class_name)):
			_call_deprecated_script_method(test_script, 'postrun_teardown', 'after_all')
			test_script.after_all()

		# This might end up being very resource intensive if the scripts
		# don't clean up after themselves.  Might have to consolidate output
		# into some other structure and kill the script objects with
		# test_script.free() instead of remove child.
		remove_child(test_script)
		#END TESTS IN SCRIPT LOOP
		_current_test = null
		_ctrls.script_progress.set_value(s + 1)
		#END TEST SCRIPT LOOP

	_end_run()

func _pass(text=''):
	_summary.tally_passed += 1
	_update_controls()
	if(_current_test):
		_new_summary.add_pass(_current_test.name, text)

func _fail(text=''):
	_summary.tally_failed += 1
	if(_current_test != null):
		var line_text = ''
		# Inner classes don't get the line number set so don't print it
		# since -1 isn't helpful
		if(_current_test.line_number != -1):
			line_text = '  at line ' + str(_current_test.line_number)
			p(line_text, LOG_LEVEL_FAIL_ONLY)
			# format for summary
			line_text =  "\n    " + line_text

		_new_summary.add_fail(_current_test.name, text + line_text)
		_current_test.passed = false

	_update_controls()

func _pending(text=''):
	if(_current_test):
		_new_summary.add_pending(_current_test.name, text)
#########################
#
# public
#
#########################

# ------------------------------------------------------------------------------
# Conditionally prints the text to the console/results variable based on the
# current log level and what level is passed in.  Whenever currently in a test,
# the text will be indented under the test.  It can be further indented if
# desired.
# ------------------------------------------------------------------------------
func p(text, level=0, indent=0):
	var str_text = str(text)
	var to_print = ""
	var printing_test_name = false

	if(level <= _log_level):
		if(_current_test != null):
			#make sure everything printed during the execution
			#of a test is at least indented once under the test
			if(indent == 0):
				indent = 1

			#Print the name of the current test if we haven't
			#printed it already.
			if(!_current_test.has_printed_name):
				to_print = "* " + _current_test.name
				_current_test.has_printed_name = true
				printing_test_name = str_text == _current_test.name

		if(!printing_test_name):
			if(to_print != ""):
				to_print += "\n"
			#Make the indent
			var pad = ""
			for i in range(0, indent):
				pad += "    "
			to_print += pad + str_text
			to_print = to_print.replace("\n", "\n" + pad)

		if(_should_print_to_console):
			print(to_print)

		_log_text += to_print + "\n"

		_ctrls.text_box.insert_text_at_cursor(to_print + "\n")

################
#
# RUN TESTS/ADD SCRIPTS
#
################

# ------------------------------------------------------------------------------
# Runs all the scripts that were added using add_script
# ------------------------------------------------------------------------------
func test_scripts(run_rest=false):
	_test_collector.set_test_class_prefix(_inner_class_prefix)
	clear_text()
	_test_collector.clear()

	if(run_rest):
		for idx in range(_ctrls.scripts_drop_down.get_selected(), _ctrls.scripts_drop_down.get_item_count()):
			_test_collector.add_script(_ctrls.scripts_drop_down.get_item_text(idx))
	else:
		_test_collector.add_script(_ctrls.scripts_drop_down.get_item_text(_ctrls.scripts_drop_down.get_selected()))

	_test_the_scripts()


# ------------------------------------------------------------------------------
# Runs a single script passed in.
# ------------------------------------------------------------------------------
func test_script(script):
	_test_collector.set_test_class_prefix(_inner_class_prefix)
	_test_collector.clear()
	_test_collector.add_script(script)
	_test_the_scripts()

# ------------------------------------------------------------------------------
# Adds a script to be run when test_scripts called
# ------------------------------------------------------------------------------
func add_script(script, select_this_one=false):
	_test_collector.set_test_class_prefix(_inner_class_prefix)
	_test_collector.add_script(script)
	_ctrls.scripts_drop_down.add_item(script)
	# Move the run_button in case the size of the path of the script caused the
	# drop down to resize.
	_ctrls.run_button.set_position(_ctrls.scripts_drop_down.get_position() + \
	                           Vector2(_ctrls.scripts_drop_down.get_size().x + 5, 0))

	if(select_this_one):
		_ctrls.scripts_drop_down.select(_ctrls.scripts_drop_down.get_item_count() -1)

# ------------------------------------------------------------------------------
# Add all scripts in the specified directory that start with the prefix and end
# with the suffix.  Does not look in sub directories.  Can be called multiple
# times.
# ------------------------------------------------------------------------------
func add_directory(path, prefix=_file_prefix, suffix=_file_extension):
	var d = Directory.new()
	# check for '' b/c the calls to addin the exported directories 1-6 will pass
	# '' if the field has not been populated.  This will cause res:// to be
	# processed which will include all files if include_subdirectories is true.
	if(path == '' or !d.dir_exists(path)):
		return
	d.open(path)
	# true parameter tells list_dir_begin not to include "." and ".." diretories.
	d.list_dir_begin(true)

	# Traversing a directory is kinda odd.  You have to start the process of listing
	# the contents of a directory with list_dir_begin then use get_next until it
	# returns an empty string.  Then I guess you should end it.
	var fs_item = d.get_next()
	var full_path = ''
	while(fs_item != ''):
		full_path = path.plus_file(fs_item)

		#file_exists returns fasle for directories
		if(d.file_exists(full_path)):
			if(fs_item.begins_with(prefix) and fs_item.find(suffix) != -1):
				add_script(full_path)
		elif(get_include_subdirectories() and d.dir_exists(full_path)):
			add_directory(full_path, prefix, suffix)

		fs_item = d.get_next()
	d.list_dir_end()

# ------------------------------------------------------------------------------
# This will try to find a script in the list of scripts to test that contains
# the specified script name.  It does not have to be a full match.  It will
# select the first matching occurrence so that this script will run when run_tests
# is called.  Works the same as the select_this_one option of add_script.
#
# returns whether it found a match or not
# ------------------------------------------------------------------------------
func select_script(script_name):
	var found = false
	var idx = 0

	while(idx < _ctrls.scripts_drop_down.get_item_count() and !found):
		if(_ctrls.scripts_drop_down.get_item_text(idx).find(script_name) != -1):
			_ctrls.scripts_drop_down.select(idx)
			found = true
		else:
			idx += 1

	return found

################
#
# MISC
#
################
# ------------------------------------------------------------------------------
# Maximize test runner window to fit the viewport.
# ------------------------------------------------------------------------------
func set_should_maximize(should):
	_should_maximize = should

func get_should_maximize():
	return _should_maximize

func maximize():
	if(is_inside_tree()):
		set_position(title_offset)
		var vp_size_offset = get_viewport().size - title_offset
		set_size(vp_size_offset / get_scale())

func disable_strict_datatype_checks(should):
	_disable_strict_datatype_checks = should

func is_strict_datatype_checks_disabled():
	return _disable_strict_datatype_checks

# ------------------------------------------------------------------------------
# Pauses the test and waits for you to press a confirmation button.  Useful when
# you want to watch a test play out onscreen or inspect results.
# ------------------------------------------------------------------------------
func end_yielded_test():
	_lgr.deprecated('end_yielded_test is no longer necessary, you can remove it.')
	#_waiting = false

# ------------------------------------------------------------------------------
# Clears the text of the text box.  This resets all counters.
# ------------------------------------------------------------------------------
func clear_text():
	_ctrls.text_box.set_text("")
	_ctrls.text_box.clear_colors()
	update()

# ------------------------------------------------------------------------------
# Get the number of tests that were ran
# ------------------------------------------------------------------------------
func get_test_count():
	return _new_summary.get_totals().tests

# ------------------------------------------------------------------------------
# Get the number of assertions that were made
# ------------------------------------------------------------------------------
func get_assert_count():
	var t = _new_summary.get_totals()
	return t.passing + t.failing

# ------------------------------------------------------------------------------
# Get the number of assertions that passed
# ------------------------------------------------------------------------------
func get_pass_count():
	return _new_summary.get_totals().passing

# ------------------------------------------------------------------------------
# Get the number of assertions that failed
# ------------------------------------------------------------------------------
func get_fail_count():
	return _new_summary.get_totals().failing

# ------------------------------------------------------------------------------
# Get the number of tests flagged as pending
# ------------------------------------------------------------------------------
func get_pending_count():
	return _new_summary.get_totals().pending

# ------------------------------------------------------------------------------
# Set whether it should print to console or not.  Default is yes.
# ------------------------------------------------------------------------------
func set_should_print_to_console(should):
	_should_print_to_console = should

# ------------------------------------------------------------------------------
# Get whether it is printing to the console
# ------------------------------------------------------------------------------
func get_should_print_to_console():
	return _should_print_to_console

# ------------------------------------------------------------------------------
# Get the results of all tests ran as text.  This string is the same as is
# displayed in the text box, and simlar to what is printed to the console.
# ------------------------------------------------------------------------------
func get_result_text():
	return _log_text

# ------------------------------------------------------------------------------
# Set the log level.  Use one of the various LOG_LEVEL_* constants.
# ------------------------------------------------------------------------------
func set_log_level(level):
	_log_level = level
	_ctrls.log_level_slider.set_value(level)

# ------------------------------------------------------------------------------
# Get the current log level.
# ------------------------------------------------------------------------------
func get_log_level():
	return _log_level

# ------------------------------------------------------------------------------
# Call this method to make the test pause before teardown so that you can inspect
# anything that you have rendered to the screen.
# ------------------------------------------------------------------------------
func pause_before_teardown():
	_pause_before_teardown = true;

# ------------------------------------------------------------------------------
# For batch processing purposes, you may want to ignore any calls to
# pause_before_teardown that you forgot to remove.
# ------------------------------------------------------------------------------
func set_ignore_pause_before_teardown(should_ignore):
	_ignore_pause_before_teardown = should_ignore
	_ctrls.ignore_continue_checkbox.set_pressed(should_ignore)

func get_ignore_pause_before_teardown():
	return _ignore_pause_before_teardown

# ------------------------------------------------------------------------------
# Set to true so that painting of the screen will occur between tests.  Allows you
# to see the output as tests occur.  Especially useful with long running tests that
# make it appear as though it has humg.
#
# NOTE:  not compatible with 1.0 so this is disabled by default.  This will
# change in future releases.
# ------------------------------------------------------------------------------
func set_yield_between_tests(should):
	_yield_between.should = should

func get_yield_between_tests():
	return _yield_between.should

# ------------------------------------------------------------------------------
# Call _process or _fixed_process, if they exist, on obj and all it's children
# and their children and so and so forth.  Delta will be passed through to all
# the _process or _fixed_process methods.
# ------------------------------------------------------------------------------
func simulate(obj, times, delta):
	for i in range(times):
		if(obj.has_method("_process")):
			obj._process(delta)
		if(obj.has_method("_physics_process")):
			obj._physics_process(delta)

		for kid in obj.get_children():
			simulate(kid, 1, delta)

# ------------------------------------------------------------------------------
# Starts an internal timer with a timeout of the passed in time.  A 'timeout'
# signal will be sent when the timer ends.  Returns itself so that it can be
# used in a call to yield...cutting down on lines of code.
#
# Example, yield to the Gut object for 10 seconds:
#  yield(gut.set_yield_time(10), 'timeout')
# ------------------------------------------------------------------------------
func set_yield_time(time, text=''):
	_yield_timer.set_wait_time(time)
	_yield_timer.start()
	var msg = '/# Yielding (' + str(time) + 's)'
	if(text == ''):
		msg += ' #/'
	else:
		msg +=  ':  ' + text + ' #/'
	p(msg, 1)
	_was_yield_method_called = true
	return self

# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
func set_yield_signal_or_time(obj, signal_name, max_wait, text=''):
	obj.connect(signal_name, self, '_yielding_callback', [true])
	_yielding_to.obj = obj
	_yielding_to.signal_name = signal_name

	_yield_timer.set_wait_time(max_wait)
	_yield_timer.start()
	_was_yield_method_called = true
	p(str('/# Yielding to signal "', signal_name, '" or for ', max_wait, ' seconds #/'))
	return self

# ------------------------------------------------------------------------------
# get the specific unit test that should be run
# ------------------------------------------------------------------------------
func get_unit_test_name():
	return _unit_test_name

# ------------------------------------------------------------------------------
# set the specific unit test that should be run.
# ------------------------------------------------------------------------------
func set_unit_test_name(test_name):
	_unit_test_name = test_name

# ------------------------------------------------------------------------------
# Creates an empty file at the specified path
# ------------------------------------------------------------------------------
func file_touch(path):
	var f = File.new()
	f.open(path, f.WRITE)
	f.close()

# ------------------------------------------------------------------------------
# deletes the file at the specified path
# ------------------------------------------------------------------------------
func file_delete(path):
	var d = Directory.new()
	var result = d.open(path.get_base_dir())
	if(result == OK):
		d.remove(path)

# ------------------------------------------------------------------------------
# Checks to see if the passed in file has any data in it.
# ------------------------------------------------------------------------------
func is_file_empty(path):
	var f = File.new()
	f.open(path, f.READ)
	var empty = f.get_len() == 0
	f.close()
	return empty

# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
func get_file_as_text(path):
	var to_return = ''
	var f = File.new()
	f.open(path, f.READ)
	to_return = f.get_as_text()
	f.close()
	return to_return
# ------------------------------------------------------------------------------
# deletes all files in a given directory
# ------------------------------------------------------------------------------
func directory_delete_files(path):
	var d = Directory.new()
	var result = d.open(path)

	# SHORTCIRCUIT
	if(result != OK):
		return

	# Traversing a directory is kinda odd.  You have to start the process of listing
	# the contents of a directory with list_dir_begin then use get_next until it
	# returns an empty string.  Then I guess you should end it.
	d.list_dir_begin()
	var thing = d.get_next() # could be a dir or a file or something else maybe?
	var full_path = ''
	while(thing != ''):
		full_path = path + "/" + thing
		#file_exists returns fasle for directories
		if(d.file_exists(full_path)):
			d.remove(full_path)
		thing = d.get_next()
	d.list_dir_end()

# ------------------------------------------------------------------------------
# Returns the instantiated script object that is currently being run.
# ------------------------------------------------------------------------------
func get_current_script_object():
	var to_return = null
	if(_test_script_objects.size() > 0):
		to_return = _test_script_objects[-1]
	return to_return

# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
func get_current_test_object():
	return _current_test

# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
func get_stubber():
	return _stubber

# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
func get_doubler():
	return _doubler

# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
func get_spy():
	return _spy

# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
func get_temp_directory():
	return _temp_directory

# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
func set_temp_directory(temp_directory):
	_temp_directory = temp_directory

# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
func get_inner_class_name():
	return _inner_class_name

# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
func set_inner_class_name(inner_class_name):
	_inner_class_name = inner_class_name

# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
func get_summary():
	return _new_summary

# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
func get_double_strategy():
	return _double_strategy

# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
func set_double_strategy(double_strategy):
	_double_strategy = double_strategy
	_doubler.set_strategy(double_strategy)

# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
func get_include_subdirectories():
	return _include_subdirectories

# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
func get_logger():
	return _lgr

# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
func set_logger(logger):
	_lgr = logger

# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
func set_include_subdirectories(include_subdirectories):
	_include_subdirectories = include_subdirectories

# #######################
# Moved method warnings.
# #######################
func moved_method(method_name):
	_lgr.deprecated('[' + method_name + '] has been moved to the Test class.  To fix, remove "gut." from in front of it.')
	_test_script_objects[-1]._fail('Method has been moved.')
	_summary.moved_methods += 1
func assert_eq(got, expected, text=""):
	moved_method('assert_eq')
func assert_ne(got, not_expected, text=""):
	moved_method('assert_ne')
func assert_gt(got, expected, text=""):
	moved_method('assert_gt')
func assert_lt(got, expected, text=""):
	moved_method('assert_lt')
func assert_true(got, text=""):
	moved_method('assert_true')
func assert_false(got, text=""):
	moved_method('assert_false')
func assert_between(got, expect_low, expect_high, text=""):
	moved_method('assert_between')
func assert_file_exists(file_path):
	moved_method('assert_file_exists')
func assert_file_does_not_exist(file_path):
	moved_method('assert_file_does_not_exist')
func assert_file_empty(file_path):
	moved_method('assert_file_empty')
func assert_file_not_empty(file_path):
	moved_method('assert_file_not_empty')
func assert_get_set_methods(obj, property, default, set_to):
	moved_method('assert_get_set_methods')
func assert_has(obj, element, text=""):
	moved_method('assert_has')
func assert_does_not_have(obj, element, text=""):
	moved_method('assert_does_not_have')
func pending(text=""):
	moved_method('pending')


################################################################################
# OneTest (INTERNAL USE ONLY)
#	Used to keep track of info about each test ran.
################################################################################
class OneTest:
	# indicator if it passed or not.  defaults to true since it takes only
	# one failure to make it not pass.  _fail in gut will set this.
	var passed = true
	# the name of the function
	var name = ""
	# flag to know if the name has been printed yet.
	var has_printed_name = false
	# the line number the test is on
	var line_number = -1
