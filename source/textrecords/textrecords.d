/**
	A simple record format processor.
*/
module textrecords.textrecords;

import std.stdio, std.conv, std.container;
import std.regex, std.algorithm, std.range;
import std.array, std.format, std.string;
import std.path, std.file, std.meta, std.traits;
import std.compiler;

import dstringutils.utils;

private auto RECORD_FIELD_REGEX = ctRegex!(`\s+(?P<key>\w+)\s{1,1}(?P<value>.*)`);
alias StdFind = std.algorithm.searching.find;

static if(version_major <= 2 && version_minor < 81)
{
	shared static this()
	{
		/*
			FIXME: If a record contains a string member the program will exit with SIGILL(illegal instruction)
			when inserting the record into the Array!T type. This is a bug in DMD/Phobos. We have to force GC init
			here. Issue 18996 on issues.dlang.org.
		*/
		auto a = "init gc".dup; // force GC init...
	}
}

private template allMembers(T)
{
	enum allMembers = __traits(allMembers, T);
}

/**
	Manages a record format.

	Example:
		--------------------------------------
		string records = "
			{
				firstName "Albert"
				lastName "Einstein"
			}

			{
				firstName "Grace"
				lastName "Hopper"
			}
		";

		struct SimpleRecord
		{
			string firstName;
			string lastName;
		}

		void main()
		{
			TextRecords!SimpleRecord collector;
			collector.parse(records);

			foreach(entry; collector.getRecords())
			{
				writeln(entry);
			}
		}
		--------------------------------------
*/
struct TextRecords(T)
{
	alias RecordArray = Array!T;
	alias StringArray = Array!string;

	/**
		Converts the record from a file to its corresponding struct T.

		Params:
			strArray = The array of lines that contains an actual record.

		Returns:
			A struct of type T filled with record values mapped to the struct members.

	*/
	private T convertToRecord(StringArray strArray)
	{
		T data;

		foreach(line; strArray)
		{
			auto re = matchFirst(line, RECORD_FIELD_REGEX);

			if(!re.empty)
			{
				immutable string key = re["key"].removeChars("\"");
				immutable string value = re["value"].removeChars("\"");

				foreach(field; allMembers!T)
				{
					if(field == key)
					{
						// This generates code in the form of: data.field=to!type(value);
						immutable string generatedCode = "data." ~ field ~ "=to!" ~ typeof(mixin("data." ~ field)).stringof ~ "(value);";
						mixin(generatedCode);
					}
				}
			}
		}

		return data;
	}

	/**
		Parses a string into an array of records.

		Params:
			records = The string of records to process.
	*/
	void parse(const string records)
	{
		auto lines = records.lineSplitter();
		StringArray strArray;

		foreach(line; lines)
		{
			if(line.canFind("{"))
			{
				strArray.clear();
			}
			else if(line.canFind("}"))
			{
				recordArray_.insert(convertToRecord(strArray));
			}
			else
			{
				strArray.insert(line);
			}
		}
	}

	/**
		Parses a string into an array of records.

		Params:
			records = The string of records to process.

		Returns:
			An $(LINK2 http://dlang.org/phobos/std_container_array.html, std.container.Array) of records.
	*/
	RecordArray parseRaw(const string records)
	{
		auto lines = records.lineSplitter();
		StringArray strArray;

		foreach(line; lines)
		{
			if(line.canFind("{"))
			{
				strArray.clear();
			}
			else if(line.canFind("}"))
			{
				recordArray_.insert(convertToRecord(strArray));
			}
			else
			{
				strArray.insert(line);
			}
		}

		return recordArray_;
	}

	/**
		Loads a file of records and parses it.

		Params:
			fileName = The name of the file to parse.

		Returns:
			true if parsing succeeded false otherwise.
	*/
	bool parseFile(const string fileName)
	{
		if(fileName.exists)
		{
			parse(fileName.readText);
			return true;
		}

		return false;
	}

	/**
		Loads a file of records and parses it.

		Params:
			fileName = The name of the file to parse.

		Returns:
			An $(LINK2 http://dlang.org/phobos/std_container_array.html, std.container.Array) of records.
	*/
	RecordArray parseFileRaw(const string fileName)
	{
		RecordArray recArray;

		if(fileName.exists)
		{
			recArray = parseRaw(fileName.readText);
		}

		return recArray;
	}

	/**
		Saves records to a file.

		Params:
			name = Name of the file to save records to.
	*/
	void save(const string name)
	{

		auto app = appender!string();
		auto f = File(name, "w");

		foreach(record; recordArray_)
		{
			app.put("{\n");

			foreach(memberName; allMembers!T)
			{
				immutable string code = "\t" ~ memberName ~ " " ~ "\"" ~ mixin("to!string(record." ~ memberName ~ ")") ~ "\"\n";
				app.put(code);
			}

			app.put("}\n\n");
		}

		f.write(app.data);
	}

	debug
	{
		/**
			Outputs each record to stdout. $(B This method is only available in debug build).
		*/
		void dump()
		{
			debug recordArray_.each!writeln;
		}
	}

	/**
		Returns the array of records.

		Returns:
			The array of records.
	*/
	auto getRecordsRaw()
	{
		return recordArray_;
	}

	alias getRecords = getRecordsRaw; // FIXME: Remove once deprecated phase is over.

	/**
		Returns a reference to the array of records.

		Returns:
			An reference to the array of records.
	*/
	ref auto getRecordsRawRef()
	{
		return recordArray_;
	}

	/**
		Finds a record(s).

		Params:
			value = The value to look for in recordField.
			amount = The number of results to return. Note passing zero will return all the results.

		Returns:
			The results of the query.

	*/
	auto find(S, string recordField)(const S value, size_t amount = 1)
	{
		auto found = filter!((T data) => mixin("data." ~ recordField) == value)(recordArray_[]).array;

		if(amount != 0)
		{
			return found.take(amount);
		}

		return found;
	}

	/**
		Finds a record(s).

		Params:
			predicate = The lambda to use to filter results.
			amount = The number of results to return. Note passing zero will return all the results.

		Returns:
			The results of the query.

	*/
	auto find(alias predicate)(size_t amount = 1)
	{
		auto found = filter!(predicate)(recordArray_[]).array;

		if(amount != 0)
		{
			return found.take(amount);
		}

		return found;
	}

	/**
		Just an overload of find that returns all results.

		Params:
			predicate = The lambda to use to filter results.

		Returns:
			The results of the query.
	*/
	auto findAll(alias predicate)()
	{
		return find!(predicate)(0);
	}

	/**
		Just an overload of find that returns all results.

		Params:
			value = The value to look for in recordField.

		Returns:
			The results of the query.
	*/
	auto findAll(S, string recordField)(const S value)
	{
		return find!(S, recordField)(value, 0);
	}

	void update(S, string recordField)(const S valueToFind, const S value, size_t amount = 1)
	{
		size_t counter;

		foreach(ref record; recordArray_)
		{
			if(mixin("record." ~ recordField ~ " == " ~ "valueToFind"))
			{
				if(counter <= amount || amount == 0)
				{
					mixin("record." ~ recordField ~ " = " ~ "value;");
				}
			}

			++counter;
		}
	}

	void updateAll(S, string recordField)(const S valueToFind, const S value)
	{
		update!(S, recordField)(valueToFind, value, 0);
	}

	void update(S, string recordField, alias predicate)(const S value, size_t amount = 1)
	{
		size_t counter;

		foreach(ref record; recordArray_)
		{
			if(predicate(record))
			{
				if(counter <= amount || amount == 0)
				{
					mixin("record." ~ recordField ~ " = " ~ "value;");
				}
			}

			++counter;
		}
	}

	void updateAll(S, string recordField, alias predicate)(const S value)
	{
		update!(S, recordField, predicate)(value, 0);
	}

	/**
			Removes a record(s).

			Params:
				value = The value to remove in recordField.
				removeCount = The number of values to remove. Note passing zero will remove everything.

	*/
	void remove(S, string recordField)(const S value, size_t removeCount = 1)
	{
		auto found = StdFind!((T data, S fieldValue) => mixin("data." ~ recordField) == fieldValue)(recordArray_[], value);

		if(removeCount != 0)
		{
			recordArray_.linearRemove(found.take(removeCount));
		}
		else
		{
			recordArray_.linearRemove(found.take(found.length));
		}
	}

	/**
			Removes a record(s).

			Params:
				predicate = The lambda to use in determining what to remove.
				removeCount = The number of values to remove. Note passing zero will remove everything.

	*/
	void remove(alias predicate)(size_t removeCount = 1)
	{
		auto found = StdFind!(predicate)(recordArray_[]);

		if(removeCount != 0)
		{
			recordArray_.linearRemove(found.take(removeCount));
		}
		else
		{
			recordArray_.linearRemove(found.take(found.length));
		}
	}

	/**
		Just an overload of remove that removes everything.

		Params:
			value = The value to remove in recordField.
	*/
	void removeAll(S, string recordField)(const S value)
	{
		remove!(S, recordField)(value, 0);
	}

	/**
			Removes all records that match predicate.

			Params:
				predicate = The lambda to use in determining what to remove.
	*/
	void removeAll(predicate)()
	{
		remove!(predicate)(0);
	}

	/**
		Determines if a value is found in a recordField.

		Params:
			recordField = The field used for finding the value.
			value = The value to find.

		Returns:
			true if found false otherwise.
	*/
	bool hasValue(S, string recordField)(const S value)
	{
		return canFind!((T data) => mixin("data." ~ recordField) == value)(recordArray_[]);
	}

	/**
		Determines if a value is found in a recordField.

		Params:
				predicate = The lambda to use in determining if the value can be found.

		Returns:
			true if found false otherwise.
	*/
	bool hasValue(alias predicate)()
	{
		return canFind!(predicate)(recordArray_[]);
	}

	/**
		Inserts a struct of type T into the record array.

		Params:
			value = The value to insert of type T.
	*/
	void insert(T value)
	{
		recordArray_.insert(value);
	}

	mixin(generateInsertMethod!T);
	mixin(generateFindMethodCode!T);
	mixin(generateUpdateMethodCode!T);
	mixin(generateHasMethodCode!T);
	mixin(generateRemoveMethodCode!T);

	RecordArray recordArray_;
	alias recordArray_ this;
}

/**
	Generates an insert method based on the members of T

	Given this struct:

	struct One
	{
		string firstWord;
	}

	The following methods will be generated:

		void insert(string firstWord)
		{
			T data;

			data.firstWord = firstWord;
			insert(data);
		}
*/
private string generateInsertMethod(T)()
{
	string code;

	code = "void insert(";

	foreach(index, memberType; typeof(T.tupleof))
	{
		code ~= memberType.stringof ~ " " ~ T.tupleof[index].stringof ~ ",";
	}

	if(code.back == ',')
	{
		code.popBack;
	}

	code ~= ")\n{\n";
	code ~= "\tT data;\n\n";


	foreach(index, memberType; typeof(T.tupleof))
	{
		string memberName = T.tupleof[index].stringof;
		code ~= "\tdata." ~  memberName ~ " = " ~ memberName ~ ";\n";
	}

	code ~= "\tinsert(data);";
	code ~= "\n}";

	return code;
}

/**
	Generates various find methods.

	Given this struct:

	struct One
	{
		string firstWord;
	}

	The following methods will be generated:

	auto findByFirstWord(const string value)
	{
		return find!(string, "firstWord")(value);
	}

	auto findAllByFirstWord(const string value)
	{
		return find!(string, "firstWord")(value, 0);
	}

	auto find(string recordField)(const string value, size_t amount = 1)
	{
		return find!(string, recordField)(value, amount);
	}

	auto findAll(string recordField)(const string value, size_t amount = 1)
	{
		return findAll!(string, recordField)(value);
	}
*/
private string generateFindMethodCode(T)()
{
	string code;

	foreach(i, memberType; typeof(T.tupleof))
	{
		immutable string memType = memberType.stringof;
		immutable string memName = T.tupleof[i].stringof;
		immutable string memNameCapitalized = memName[0].toUpper.to!string ~ memName[1..$];

		code ~= format(q{
			auto findBy%s(const %s value)
			{
				return find!(%s, "%s")(value);
			}
		}, memNameCapitalized, memType, memType, memName);

		code ~= format(q{
			auto findAllBy%s(const %s value)
			{
				return find!(%s, "%s")(value, 0);
			}
		}, memNameCapitalized, memType, memType, memName);
	}

	foreach(i, memberType; NoDuplicates!(Fields!T))
	{
		immutable string memType = memberType.stringof;
		immutable string memName = T.tupleof[i].stringof;
		immutable string memNameCapitalized = memName[0].toUpper.to!string ~ memName[1..$];

		code ~= format(q{
			auto find(string recordField)(const %s value, size_t amount = 1)
			{
				return find!(%s, recordField)(value, amount);
			}
		}, memType, memType);

		code ~= format(q{
			auto findAll(string recordField)(const %s value, size_t amount = 1)
			{
				return findAll!(%s, recordField)(value);
			}
		}, memType, memType);
	}

	return code;
}

/**
	Generates various update methods.

	Given this struct:

	struct One
	{
		string firstWord;
	}

	The following methods will be generated:

	void updateByFirstWord(const string valueToFind, const string value, size_t amount = 1)
	{
		update!(string, "firstWord")(valueToFind, value, amount);
	}

	void updateAllByFirstWord(const string valueToFind, const string value)
	{
		updateAll!(string, "firstWord")(valueToFind, value);
	}

	void update(string recordField)(const string valueToFind, const string value, size_t amount = 1)
	{
		update!(string, recordField)(valueToFind, value, amount);
	}

	void updateAll(string recordField)(const string valueToFind, const string value)
	{
		updateAll!(string, recordField)(valueToFind, value);
	}

	void update(string recordField, alias predicate)(const string value, size_t amount = 1)
	{
		update!(string, recordField, predicate)(valueToFind, value, amount);
	}

	void updateAll(string recordField, alias predicate)(const string value)
	{
		updateAll!(string, recordField, predicate)(valueToFind, value);
	}
*/
private string generateUpdateMethodCode(T)()
{
	string code;

	foreach(i, memberType; typeof(T.tupleof))
	{
		immutable string memType = memberType.stringof;
		immutable string memName = T.tupleof[i].stringof;
		immutable string memNameCapitalized = memName[0].toUpper.to!string ~ memName[1..$];

		code ~= format(q{
			void updateBy%s(const %s valueToFind, const %s value, size_t amount = 1)
			{
				update!(%s, "%s")(valueToFind, value, amount);
			}
		}, memNameCapitalized, memType, memType, memType, memName);

		code ~= format(q{
			void updateAllBy%s(const %s valueToFind, const %s value)
			{
				updateAll!(%s, "%s")(valueToFind, value);
			}
		}, memNameCapitalized, memType, memType, memType, memName);
	}

	foreach(i, memberType; NoDuplicates!(Fields!T))
	{
		immutable string memType = memberType.stringof;
		immutable string memName = T.tupleof[i].stringof;
		immutable string memNameCapitalized = memName[0].toUpper.to!string ~ memName[1..$];

		code ~= format(q{
			void update(string recordField)(const %s valueToFind, const %s value, size_t amount = 1)
			{
				update!(%s, recordField)(valueToFind, value, amount);
			}
		}, memType, memType, memType);

		code ~= format(q{
			void updateAll(string recordField)(const %s valueToFind, const %s value)
			{
				updateAll!(%s, recordField)(valueToFind, value);
			}
		},  memType, memType, memType);

		code ~= format(q{
			void update(string recordField, alias predicate)(const %s value, size_t amount = 1)
			{
				update!(%s, recordField, predicate)(valueToFind, value, amount);
			}
		}, memType, memType);

		code ~= format(q{
			void updateAll(string recordField, alias predicate)(const %s value)
			{
				updateAll!(%s, recordField, predicate)(valueToFind, value);
			}
		},  memType, memType);
	}

	return code;
}
/**
	Generates various hasValue methods.

	Given this struct:

	struct One
	{
		string firstWord;
	}

	The following methods will be generated:

	bool hasFirstWord(const string value)
	{
		return hasValue!(string, "firstWord")(value);
	}

	bool hasValue(string recordField)(const string value)
	{
		return hasValue!(string, "firstWord")(value);
	}

*/
private string generateHasMethodCode(T)()
{
	string code;

	foreach(i, memberType; typeof(T.tupleof))
	{
		immutable string memType = memberType.stringof;
		immutable string memName = T.tupleof[i].stringof;
		immutable string memNameCapitalized = memName[0].toUpper.to!string ~ memName[1..$];

		code ~= format(q{
			bool has%s(const %s value)
			{
				return hasValue!(%s, "%s")(value);
			}
		}, memNameCapitalized, memType, memType, memName);
	}

	foreach(i, memberType; NoDuplicates!(Fields!T))
	{
		immutable string memType = memberType.stringof;
		immutable string memName = T.tupleof[i].stringof;
		immutable string memNameCapitalized = memName[0].toUpper.to!string ~ memName[1..$];

		code ~= format(q{
			bool hasValue(string recordField)(const %s value)
			{
				return hasValue!(%s, recordField)(value);
			}
		}, memType, memType);
	}

	return code;
}

/**
	Generates various remove methods.

	Given this struct:

	struct One
	{
		string firstWord;
	}

	The following methods will be generated:

	void removeByFirstWord(const string valueToFind, size_t amount = 1)
	{
		remove!(string, "firstWord")(valueToFind, amount);
	}

	void removeAllByFirstWord(const string valueToFind)
	{
		removeAll!(string, "firstWord")(valueToFind);
	}

	void remove(string recordField)(const string valueToFind, size_t amount = 1)
	{
		remove!(string, recordField)(valueToFind, amount);
	}

	void removeAll(string recordField)(const string valueToFind)
	{
		removeAll!(string, recordField)(valueToFind);
	}

*/
private string generateRemoveMethodCode(T)()
{
	string code;

	foreach(i, memberType; typeof(T.tupleof))
	{
		immutable string memType = memberType.stringof;
		immutable string memName = T.tupleof[i].stringof;
		immutable string memNameCapitalized = memName[0].toUpper.to!string ~ memName[1..$];

		code ~= format(q{
			void removeBy%s(const %s valueToFind, size_t amount = 1)
			{
				remove!(%s, "%s")(valueToFind, amount);
			}
		}, memNameCapitalized, memType, memType, memName);

		code ~= format(q{
			void removeAllBy%s(const %s valueToFind)
			{
				removeAll!(%s, "%s")(valueToFind);
			}
		}, memNameCapitalized, memType, memType, memName);

	}

	foreach(i, memberType; NoDuplicates!(Fields!T))
	{
		immutable string memType = memberType.stringof;
		immutable string memName = T.tupleof[i].stringof;
		immutable string memNameCapitalized = memName[0].toUpper.to!string ~ memName[1..$];

		code ~= format(q{
			void remove(string recordField)(const %s valueToFind, size_t amount = 1)
			{
				remove!(%s, recordField)(valueToFind, amount);
			}
		}, memType, memType);

		code ~= format(q{
			void removeAll(string recordField)(const %s valueToFind)
			{
				removeAll!(%s, recordField)(valueToFind);
			}
		},  memType, memType);
	}

	return code;
}

///
unittest
{
	import std.stdio : writeln;
	import dshould;

	immutable string data =
	q{
		{
			firstName "Albert"
			lastName "Einstein"
		}

		{
			firstName "John"
			lastName "Doe"
		}

		{
			firstName "Albert"
			lastName "Einstein"
		}
	};

	struct NameData
	{
		string firstName;
		string lastName;
	}

	writeln("Processing records for NameData:");

	TextRecords!NameData collector;
	collector.parse(data);

	auto records = collector.getRecordsRaw();

	records.front.firstName.should.equal("Albert");
	records.back.firstName.should.equal("Albert");
	records.length.should.equal(3);
	records[0].firstName.should.equal("Albert");

	// Since TextRecords supports alias this we can also use collector directly without calling getRecordsRaw.
	collector.front.firstName.should.equal("Albert");
	collector.back.firstName.should.equal("Albert");
	collector.length.should.equal(3);
	collector[0].firstName.should.equal("Albert");

	collector.dump();
	writeln;

	auto foundRecords = collector.findAll!(string, "firstName")("Albert");
	foundRecords.length.should.equal(2);

	bool found = collector.hasValue!(string, "firstName")("Albert");
	bool notFound = collector.hasValue!(string, "firstName")("Tom");
	found.should.equal(true);
	notFound.should.equal(false);

	found = collector.hasFirstName("Albert");
	notFound = collector.hasFirstName("Hana");
	found.should.equal(true);
	notFound.should.equal(false);

	found = collector.hasValue!("firstName")("Albert");
	notFound = collector.hasValue!("firstName")("Tom");
	found.should.equal(true);
	notFound.should.equal(false);

	writeln("Saving...");
	collector.save("test.data");

	immutable string variedData =
	q{
		{
			name "Albert Einstein"
			id "100"
		}

		{
			name "George Washington"
			id "200"
		}

		{
			name "Takahashi Ohmura"
			id "100"
		}

		{
			name "Nakamoto Suzuka"
			id "100"
		}
	};

	struct VariedData
	{
		string name;
		size_t id;
	}

	TextRecords!VariedData variedCollector;

	variedCollector.parse(variedData);
	variedCollector.length.should.equal(4);
	//variedCollector.parseFile(variedData); // FIXME: Add temporary file.

	auto variedFoundRecords = variedCollector.findAll!(size_t, "id")(100);
	variedFoundRecords.length.should.equal(3);

	auto variedRecords = variedCollector.getRecordsRaw();
	variedCollector.dump();

	bool canFindValue = canFind!((VariedData data, size_t id) => data.id == id)(variedCollector[], 100);
	canFindValue.should.equal(true);

	canFindValue = variedCollector.hasValue!((VariedData data) => data.id == 100); // Somewhat easier to use than canFind.
	canFindValue.should.equal(true);

	canFindValue = variedCollector.hasId(100);
	canFindValue.should.equal(true);

	canFindValue = variedCollector.hasValue!("id")(100);
	canFindValue.should.equal(true);

	variedCollector.findAllById(100).length.should.equal(3);

	variedCollector.remove!(size_t, "id")(100);
	variedCollector.length.should.equal(3);

	variedCollector.removeAll!(size_t, "id")(100);
	variedCollector.length.should.equal(1);

	immutable bool canFindValueInvalid = canFind!((VariedData data, size_t id) => data.id == id)(variedCollector[], 999);
	canFindValueInvalid.should.equal(false);

	VariedData insertData;
	variedCollector.insert(insertData);
	variedCollector.length.should.equal(2);

	variedCollector.insert("Utada Hikaru", 111);
	variedCollector.length.should.equal(3);

	auto record = variedCollector.find!(size_t, "id")(111);
	record[0].name.should.equal("Utada Hikaru");

	auto usingNamedMethod = variedCollector.findById(111);
	usingNamedMethod[0].name.should.equal("Utada Hikaru");

	variedCollector.save("varied.db");

	immutable string irrData =
	q{
		{
			nickName "Lisa"
			realName "Melissa"
			id "100"
		}

		{
			nickName "Liz"
			realName "Elizabeth Rogers"
			id "122"
		}
		{
			nickName "hikki"
			realName "Utada Hikaru"
			id "100"
		}
	};

	struct IrregularNames
	{
		string realName;
		string nickName;
		size_t id;
	}

	TextRecords!IrregularNames irrCollector;
	irrCollector.parse(irrData);

	auto idRecords = irrCollector.findAllById(100);
	idRecords[1].realName.should.equal("Utada Hikaru");

	auto nickNameRecords = irrCollector.findAllByNickName("hikki");
	nickNameRecords[0].realName.should.equal("Utada Hikaru");

	irrCollector.update!(size_t, "id", (IrregularNames data) => data.id == 122 && data.nickName == "Liz")(333, 0);
	auto idChange = irrCollector.findById(333);
	idChange.length.should.equal(1);

	irrCollector.updateAllById(100, 666);
	idChange = irrCollector.findAllById(666);
	idChange.length.should.equal(2);

	idChange = irrCollector.findAll!("id")(666);
	idChange.length.should.equal(2);

	idChange = irrCollector.find!((IrregularNames data) => data.id == 666)(0);
	idChange.length.should.equal(2);

	idChange = irrCollector.findAll!((IrregularNames data) => data.id == 666)();
	idChange.length.should.equal(2);

	irrCollector.removeById(666);
	idChange = irrCollector.findAll!((IrregularNames data) => data.id == 666)();
	idChange.length.should.equal(1);

	irrCollector.insert("Bobby", "Bob", 354);
	irrCollector.insert("David", "Dave", 355);
	irrCollector.insert("Jeanie", "Jean", 356);
	irrCollector.insert("Jerry", "Jer", 356);
	irrCollector.length.should.equal(6);

	irrCollector.removeAllById(356);
	irrCollector.length.should.equal(4);
	/*writeln;writeln;

	struct One
	{
		string firstWord;
		size_t id;
		string last;
	}
	writeln(generateHasMethodCode!NameData);*/
}
