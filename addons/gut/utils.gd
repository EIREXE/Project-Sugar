var _Logger = load('res://addons/gut/logger.gd') # everything should use get_logger
var Stubber = load('res://addons/gut/stubber.gd')
var Doubler = load('res://addons/gut/doubler.gd')
var Spy = load('res://addons/gut/spy.gd')
var StubParams = load('res://addons/gut/stub_params.gd')
var ThingCounter = load('res://addons/gut/thing_counter.gd')
const GUT_METADATA = '__gut_metadata_'

enum DOUBLE_STRATEGY{
	FULL,
	PARTIAL
}

# ------------------------------------------------------------------------------
# Everything should get a logger through this.
#
# Eventually I want to make this get a single instance of a logger but I'm not
# sure how to do that without everything having to be in the tree which I
# DO NOT want to to do.  I'm thinking of writings some instance ids to a file
# and loading them in the _init for this.
# ------------------------------------------------------------------------------
func get_logger():
	return _Logger.new()

# ------------------------------------------------------------------------------
# Returns an array created by splitting the string by the delimiter
# ------------------------------------------------------------------------------
func split_string(to_split, delim):
	var to_return = []

	var loc = to_split.find(delim)
	while(loc != -1):
		to_return.append(to_split.substr(0, loc))
		to_split = to_split.substr(loc + 1, to_split.length() - loc)
		loc = to_split.find(delim)
	to_return.append(to_split)
	return to_return

# ------------------------------------------------------------------------------
# Returns a string containing all the elements in the array seperated by delim
# ------------------------------------------------------------------------------
func join_array(a, delim):
	var to_return = ''
	for i in range(a.size()):
		to_return += str(a[i])
		if(i != a.size() -1):
			to_return += str(delim)
	return to_return

# ------------------------------------------------------------------------------
# return if_null if value is null otherwise return value
# ------------------------------------------------------------------------------
func nvl(value, if_null):
	if(value == null):
		return if_null
	else:
		return value

# ------------------------------------------------------------------------------
# returns true if the object has been freed, false if not
#
# From what i've read, the weakref approach should work.  It seems to work most
# of the time but sometimes it does not catch it.  The str comparison seems to
# fill in the gaps.  I've not seen any errors after adding that check.
# ------------------------------------------------------------------------------
func is_freed(obj):
	var wr = weakref(obj)
	return !(wr.get_ref() and str(obj) != '[Deleted Object]')

func is_not_freed(obj):
	return !is_freed(obj)

func is_double(obj):
	return obj.get(GUT_METADATA) != null
