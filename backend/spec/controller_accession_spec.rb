require 'spec_helper'

def create_nobody_user
  create(:user, :username => 'nobody')

  viewers = JSONModel(:group).all(:group_code => "repository-viewers").first
  viewers.member_usernames = ['nobody']
  viewers.save
end


describe 'Accession controller' do

  it "lets you create an accession and get it back" do
    opts = {:title => 'The accession title'}
    
    id = create(:json_accession, opts).id
    JSONModel(:accession).find(id).title.should eq(opts[:title])
  end


  it "lets you list all accessions" do
    create(:json_accession)
    JSONModel(:accession).all.count.should eq(1)
  end


  it "fails when you try to update an accession that doesn't exist" do
    acc = build(:json_accession)
    acc.uri = "#{$repo}/accessions/9999"

    expect { acc.save }.to raise_error
  end


  it "fails on missing properties" do
    JSONModel::strict_mode(false)

    expect { JSONModel(:accession).from_hash("id_0" => "abcdef") }.to raise_error(JSONModel::ValidationException)

    begin
      acc = JSONModel(:accession).from_hash("id_0" => "abcdef")
    rescue JSONModel::ValidationException => e
      errors = ["title", "accession_date"]
      warnings = ["content_description", "condition_description"]

      (e.errors.keys - errors).should eq([])
      (e.warnings.keys - warnings).should eq([])
    end

    JSONModel::strict_mode(true)
  end


  it "supports updates" do
    acc = create(:json_accession)

    acc.id_1 = "5678"
    acc.save

    JSONModel(:accession).find(acc.id).id_1.should eq("5678")
  end


  it "knows its own URI" do
    acc = create(:json_accession)
    JSONModel(:accession).find(acc.id).uri.should eq("#{$repo}/accessions/#{acc.id}")
  end


  it "won't let you overwrite the current version of a record with a stale copy" do

    acc = create(:json_accession)

    acc1 = JSONModel(:accession).find(acc.id)
    acc2 = JSONModel(:accession).find(acc.id)

    acc1.id_1 = "5678"
    acc1.save

    # Working off the stale copy
    acc2.id_1 = "9999"
    expect {
      acc2.save
    }.to raise_error(ConflictException)

  end


  it "creates an accession with a rights statement" do
    acc = JSONModel(:accession).from_hash("id_0" => "1234",
                                          "title" => "The accession title",
                                          "content_description" => "The accession description",
                                          "condition_description" => "The condition description",
                                          "accession_date" => "2012-05-03",
                                          "rights_statements" => [
                                            {
                                              "identifier" => "abc123",
                                              "rights_type" => "intellectual_property",
                                              "ip_status" => "copyrighted",
                                              "jurisdiction" => "AU",
                                            }
                                          ]).save
    JSONModel(:accession).find(acc).rights_statements.length.should eq(1)
    JSONModel(:accession).find(acc).rights_statements[0]["identifier"].should eq("abc123")
    JSONModel(:accession).find(acc).rights_statements[0]["active"].should eq(true)
  end


  it "creates an accession with a deaccession" do
    acc = JSONModel(:accession).from_hash("id_0" => "1234",
                                          "title" => "The accession title",
                                          "content_description" => "The accession description",
                                          "condition_description" => "The condition description",
                                          "accession_date" => "2012-05-03",
                                          "deaccessions" => [
                                            {
                                              "whole_part" => false,
                                              "description" => "A description of this deaccession",
                                              "date" => {
                                                            "date_type" => "single",
                                                            "label" => "deaccession",
                                                            "begin" => "2012-05-14",
                                                          },
                                            }
                                          ]).save
    JSONModel(:accession).find(acc).deaccessions.length.should eq(1)
    JSONModel(:accession).find(acc).deaccessions[0]["whole_part"].should eq(false)
    JSONModel(:accession).find(acc).deaccessions[0]["date"]["begin"].should eq("2012-05-14")
  end


  it "doesn't show accessions for other repositories when listing " do
    create(:json_accession)
    JSONModel(:accession).all.count.should eq(1)

    create(:repo)
    JSONModel(:accession).all.count.should eq(0)
  end


  it "doesn't show suppressed accessions when listing" do
    3.times do
      create(:json_accession)
    end

    create_nobody_user

    accession = create(:json_accession)
    accession.suppressed = true

    as_test_user('nobody') do
      JSONModel(:accession).all.count.should eq(3)
    end
  end


  it "doesn't give you any schtick if you request a suppressed accession as a manager" do
    accession = create(:json_accession)
    accession.suppressed = true

    returned_accession = JSONModel(:accession).find(accession.id)

    returned_accession.suppressed.should eq(true)
  end


  it "suppresses events that link to the current accession if they don't link to any other record" do
    test_agent = create(:json_agent_person)
    test_accession = create(:json_accession)

    event = create(:json_event,
                   :linked_agents => [{
                                        'ref' => test_agent.uri,
                                        'role' => generate(:agent_role)
                                      }],
                   :linked_records => [{
                                         'ref' => test_accession.uri,
                                         'role' => generate(:record_role)
                                       }])

    create_nobody_user

    as_test_user('nobody') do
      JSONModel(:event).find(event.id).should_not eq(nil)
    end

    test_accession.suppressed = true

    as_test_user('nobody') do
      JSONModel(:event).find(event.id).should be(nil)
    end

  end

end