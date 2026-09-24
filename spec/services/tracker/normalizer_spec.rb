require "rails_helper"

RSpec.describe Tracker::Normalizer do
  describe ".company_key" do
    {
      "Acme Technologies Pvt. Ltd." => "acme",
      "Acme, Inc." => "acme",
      "ACME LLC" => "acme",
      "Northwind Solutions Private Limited" => "northwind",
      "Tata Consultancy Services" => "tata consultancy services",
      "AT&T" => "at and t",
      "  Globex   Corp. " => "globex",
      "Solutions" => "solutions"
    }.each do |name, key|
      it("normalizes #{name.inspect} to #{key.inspect}") { expect(described_class.company_key(name)).to eq(key) }
    end

    it "returns nil for blank names" do
      expect(described_class.company_key(nil)).to be_nil
      expect(described_class.company_key(" .. ")).to be_nil
    end
  end

  describe ".role_key" do
    it "drops punctuation, parentheticals and trailing requisition IDs" do
      expect(described_class.role_key("Software Engineer II (Backend) - R12345")).to eq("software engineer ii")
      expect(described_class.role_key("SDE-2 [Remote]")).to eq("sde 2")
    end

    it "returns nil for blank roles" do
      expect(described_class.role_key("")).to be_nil
    end
  end

  describe ".domain_company_key" do
    it "picks the company label from a corporate domain" do
      expect(described_class.domain_company_key("careers.acme.co.in")).to eq("acme")
      expect(described_class.domain_company_key("mail.globex.com")).to eq("globex")
      expect(described_class.domain_company_key("initech.ai")).to eq("initech")
    end

    it "refuses ATS, job-board and personal domains" do
      %w[us.greenhouse-mail.io hire.lever.co acme.myworkdayjobs.com naukri.com gmail.com].each do |domain|
        expect(described_class.domain_company_key(domain)).to be_nil, domain
      end
    end
  end

  describe ".ats_domain" do
    it "matches subdomains to the configured ATS entry" do
      expect(described_class.ats_domain("hire.lever.co")).to eq("lever.co")
      expect(described_class.ats_domain("notlever.co")).to be_nil
    end
  end
end
