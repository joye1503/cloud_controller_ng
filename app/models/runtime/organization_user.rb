module VCAP::CloudController
  class OrganizationUser < Sequel::Model(:organizations_users)
    many_to_one :user
    many_to_one :organization

    def_column_alias :guid, :role_guid

    def before_create
      self.guid = SecureRandom.uuid
    end

    def validate
      validates_unique [:organization_id, :user_id]
      validates_presence :organization_id
      validates_presence :user_id
    end

    def type
      @type ||= RoleTypes::ORGANIZATION_USER
    end
  end
end
