#  back\_to\_the\_fixture

Based on [ar_fixtures](https://github.com/topfunky/ar_fixtures) by Geoffrey Grosenbach with additional improvements and features by Russell Jennings

back\_to\_the\_fixture let's you export your ActiveRecord models to reloadable fixtures for tests or database population. 
It's been updated for rails 3 and has some new and improved functionality.

## But aren't fixtures dead?

Most people preffer to use factories over fixtures for testing purposes because working with and maintaining fixtures,
especially for tests, can be unwieldy. However, fixtures can still be useful in other scenarios:

  * Static models, like a `MembershipPlan`, where it's a few records that should be the same in all enviroments. 
  * Testing complex modeling, where there is a network of record relationships and conditions
  * Exporting records from production for use in development
  * Snapshot & backup of records 
  * Simple Export / Import

## Getting Started 

Put this in your gemfile and run bundle install

```
gem 'back_to_the_fixture', :git => 'https://github.com/meesterdude/back_to_the_fixture.git'
```

Let's go through some examples in the rails console

## ERB

ERB is handled by `Erubis`. Because models may contain ERB in their attributes, a seperate syntax is required for parsing the fixtures. You can define ERB in your fixture files using double-percent sign tags (`<%% %%>`). Regular ERB tags are left in-tact. 

## ar_fixtures details

These commands extend `ActiveModel` and are originally from `ar_fixtures`, with some update and improvements

### Methods 

#### Model.to_fixture

Quickly output a model to a fixture file. Takes a few options:

 * `:save_path` defaults to 'fixtures/models'
 * `:save_name` defaults to the Model.table_name
 * `:append` if true, will open the file in append mode and remove the leading yaml dashes. otherwise by default it will overwrite the contents.

You can pass additional options, which will get passed on to a `.where()` call. But you'll probably want to have the records already when you call the command. 

```
> Customer.where(:id => 2).to_fixture
=> true
> Customer.where(:id => 2).to_fixture(:save_name => "backup.yml")
=> true
```

#### Model.load\_from\_file

Takes a relative path to a fixture file as it's only parameter, executes destroy_all on the model and resets the table sequence. 

```
> Customer.load_from-file('fixtures/models/customer.yml')
=> true
```

## back\_to\_the\_fixture details

Dumping one model is quick and easy, but it isn't very flexible. If you have a lot of data that depends on other data, it can get quite cumbersome to manage it all. Originally, I wanted to be able to do it all automatically using reflections on associations; but when presented with recursive relationships it became non-trivial to identify which direction to things should be approached.

### Templates 

To solve the aforementioned problem, a map must be constructed that outlines how the modeling is 'climbed'. It's just a simple hash, but doing it in yaml makes it much easier to manage. Let's take a look at a sample. 

```
---
customers_with_broken_cart:
- stores
- customers:
    grab:
    - favorites
    - carts
    - mailing_address
    - orders:
        hard_limit: 5
        grab:
        - line_items:
            hard_limit: 3
    hard_limit: 3
    order: created_at ASC
```
#### Walkthrough

 * The first line, `customers_with_broken_cart` is how a particular template is selected. 
 * The trunk models we'll be working with are "Store" and "Customer"
 * for Store, it will grab all the stores. 
 * For customers, it will be ordered by created_at, and will be limited to 3. 
 * for each customer
  * grab all their favorites
  * grab all their carts
  * grab their mailing_address
  * grab their orders( but only grab 5, and for each of those 5 orders grab at most 3 line_items )

#### Specifications
* the root keys are custom identifiers. It can be named anything, but best stick to underscores.
* the values for each root key is an array
* each array value can either be a symbol or a hash
* if it's a hash, the first key denotes the model, and the value is a hash of options
* for each hash of options, the following are permitted:
  * `:grab` takes an array of relations to call on each record from the root array. As before, it can be a hash or a symbol.
  * `:where` parameters to pass onto this relation
  * `:order` parameters to pass onto this relation
  * `:query_limit` parameter to limit the working size of the query
  * `:limit_by` takes a hash who's key is the attribute and value the number of each to keep. for example, `{:country => 3}` will return up to 3 records for each country
  * `:hard_limit` parameter is for when you want to set a hard limit after limit_by has been factored in. So you can take one from each country, but have only 10 in total. 
  * `:sanitize` takes hash of parameters to be merged in for each record. Can also define ERB to parse; triple percent blocks (`<%%% %%%>`) will get executed before the fixture is written, while double get parsed on import. Regular ERB tags are ignored. 
* you can nest this structuring with the aforementioned options to climb your modeling

More information available in the `dump_tree` method documentation.

### Trees
A tree is a collection of records from various models. It can also be considered a "slice" of your database. When outputting to file, you can either output to one file, or a tree directory with a file for each model. 

More information available in the `dump_tree` method documentation.

### Methods

#### BackToTheFixture.dump_tree
Collects records from various models and outputs them to a fixture file or files. 

##### options

 * `:template` can be a string of the relative path to a fixture template YAML file, or the hash itself. See the 'Templates' section for more info. 
 * `:template_key` select the root_key from the template to use. defaults to the first key of template
 * `:save_path` controls the relative path of output. 
 * `:save_name` is the name of the tree to save. defaults to to `#{root_key}_tree.yml`
 * `:split` if true, will split the tree across multiple YAML files, one for each model, in a directory with the template_key name. :save_path overrides the directory to write to. 
 * `:append` if true, will append to files and remove leading YAML dashes. Be careful when using on a tree file. 
 * `:merge` if true, will read in the existing file, add in the new records and models and then rewrite it out. Will not parse any ERB of the file. 

##### Examples

```
> BackToTheFixture.dump_tree(:template => "fixtures/templates/new_users.yml", :template_key => :noobs)
=> true
> BackToTheFixture.dump_tree(:template => {:noobs => [{:users => {:grab => [:posts], :query_limit => 3, :order => 'created_at DESC'}}]}, :split => true)
=> true
```

#### BackToTheFixture.load_tree

Imports fixtures into the relevant models

##### parameters 
* The first is a a single file or directory, or an array of files & directories. if directory, looks for files non-recursivly with '.yml' in their name (so '.yml.erb' is ok, too.)
* The second is a hash of options.

##### options
* `:except_models` takes an array of models to skip
* `:reset_sequence` if true, will reset the database sequencing
* `:destroy_all` if true, will destroy all records in the models before populating. 
* `:except_attributes` takes a hash, allows you to prevent certain attributes from getting inserted, like id. 
  * pass in the model name with attributes to skip
  * and/or pass in a `:global` that will apply to all records

##### Examples

```
> BackToTheFixture.load_tree('fixtures/trees/events_tree.yml', {:except_models => [:venue]})
=> true
> BackToTheFixture.load_tree('fixtures/models/seed', {except_attributes: {global: [:id], event: [:launch_codes]}, destroy_all: true})
=> true
```

## License

The MIT License (MIT)

Copyright (c) 2013 Russell Jennings

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
 




