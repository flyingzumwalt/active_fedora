require 'spec_helper'

require 'active_fedora'
require "rexml/document"

describe ActiveFedora::File do
  context "stand alone operation" do
    it "should save" do
      subject.content = "some stuff"
      subject.save
      expect(subject).not_to be_new_record
    end
  end

  context "stand alone operation with UploadedFile" do
    before(:all) do
      module ActionDispatch
        module Http
          class UploadedFile

            def initialize
              @content = StringIO.new("hello world")
            end

            def read(a, b)
              return @content.read(a, b)
            end
            
            def size
              @content.length
            end

          end
        end
      end
    end

    it "should save" do
      subject.content = ActionDispatch::Http::UploadedFile.new
      subject.save
      expect(subject).not_to be_new_record
    end
  end

  context "when autocreate is true" do
    before(:all) do
      class MockAFBase < ActiveFedora::Base
        has_metadata "descMetadata", type: ActiveFedora::QualifiedDublinCoreDatastream, autocreate: true
      end
    end

    after(:all) do
      Object.send(:remove_const, :MockAFBase)
    end

    let(:test_object) { MockAFBase.create }

    after do
      test_object.destroy
    end

    let(:descMetadata) {  test_object.attached_files["descMetadata"] }

    describe "the datastream" do
      subject { descMetadata }
      it { should be_a_kind_of(ActiveFedora::File) }
    end

    describe "#content" do
      subject { descMetadata.content }
      it { should_not be_nil }
    end

    describe "#described_by" do
      subject { descMetadata.described_by }
      it { should eq descMetadata.uri + '/fcr:metadata' }
    end


    context "an XML datastream" do
      let(:xml_content) { Nokogiri::XML::Document.parse(descMetadata.content) }
      let(:title) { Nokogiri::XML::Element.new "title", xml_content }
      before do
        title.content = "Test Title"
        xml_content.root.add_child title

        allow(descMetadata).to receive(:before_save)
        descMetadata.content = xml_content.to_s
        descMetadata.save
      end

      let(:found) { Nokogiri::XML::Document.parse(test_object.reload.descMetadata.content) }

      subject { found.xpath('//dc/title/text()').first.inner_text }
      it { should eq title.content }
    end

    context "a blob datastream" do
      let(:dsid) { "ds#{Time.now.to_i}" }
      let(:content) { fixture('dino.jpg') }
      let(:datastream) { ActiveFedora::File.new.tap { |ds| ds.content = content } }

      before do
        test_object.attach_file(datastream, dsid)
        test_object.save
      end

      it "should not be changed" do
        expect(test_object.attached_files[dsid]).to_not be_changed
      end

      it "should be able to read the content from fedora" do
        content.rewind
        expect(test_object.attached_files[dsid].content).to eq content.read
      end

      describe "streaming the response" do
        let(:stream_reader) { double }
        it "should stream the response" do
          expect(stream_reader).to receive(:read).at_least(:once)
          test_object.attached_files[dsid].stream { |buff| stream_reader.read(buff) }
        end

        context "with a range request" do
          before do
            test_object.add_file_datastream('one1two2threfour', dsid: 'webm', mime_type: 'video/webm')
            test_object.save!
          end
          subject { str = ''; test_object.webm.stream(range) {|chunk| str << chunk }; str }
          context "whole thing" do
            let(:range) { 'bytes=0-15' }
            it { should eq 'one1two2threfour'}
          end
          context "open ended" do
            let(:range) { 'bytes=0-' }
            it "should get a response" do
              expect(subject).to eq 'one1two2threfour'
            end
          end
          context "not starting at the beginning" do
            let(:range) { 'bytes=3-15' }
            it { should eq '1two2threfour'}
          end
          context "not ending at the end" do
            let(:range) { 'bytes=4-11' }
            it { should eq 'two2thre'}
          end
        end
      end
    end
  end
end
