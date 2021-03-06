require 'application/index_adapter/elasticsearch'
require 'application/index'

class User < ActiveRecord::Base

  acts_as_paranoid


  has_many :oauth2_identities

  has_one :position, dependent: :destroy
  has_one :organization, through: :position

  has_many :idea_roles, dependent: :destroy
  has_many :idea_votes, dependent: :destroy

  has_many :project_roles, dependent: :destroy
  has_many :project_votes, dependent: :destroy

  has_many :events

  has_many :groups, :through => :user_groups
  has_many :user_groups

  has_many :created_groups, :foreign_key => 'user_id', :class_name => 'Group'

  has_many :competency_users, dependent: :destroy
  has_many :competencies, through: :competency_users

  has_many :resource_users, dependent: :destroy
  has_many :resources, through: :resource_users

  has_many :comments, dependent: :destroy

  has_many :user_badges, dependent: :destroy
  has_many :badges, through: :user_badges

  validates :name_last, :allow_nil => false, :presence => true
  validates :email, :allow_nil => false, :presence => true
  #validates :password, :format => {:with => /\A(?=.*[a-zA-Z])(?=.*[0-9]).{8,}\Z/}

  attr_accessor :reset_token

  attr_html_reader :biography
  attr_html_reader :mailing_address, :nl

  attr_accessor :password,
                :password_confirmation

  scope :idea_founders, -> (idea) { includes(:idea_roles).where(idea_roles: { idea_id: idea, founder: true }) }
  scope :where_local, -> { where.not(:password_hash => nil) }
  scope :public_profiles, -> { where(:hidden => false) }

  def display_name format = :fl
    str = ''
    str << "#{name_first} " if format == :fml or format == :fl or format == :fmls
    str << "#{name_middle[0,1].capitalize}. " if (format == :fml or format == :fmls) and name_middle
    str << name_last
    str << ", #{name_suffix}" if format == :fmls
    str << ", #{name_first}" if format == :lfm or format == :lf
    str << " #{name_middle[0,1].capitalize}." if format == :lfm and name_middle
    str
  end

  def User.new_token
    SecureRandom.urlsafe_base64
  end

  def User.digest(string)
    BCrypt::Password.create(string)
  end

  def create_reset_digest
    if self.reset_token == nil
      self.reset_token = User.new_token
      update_attribute(:reset_digest,  User.digest(reset_token))
      update_attribute(:reset_sent_at, Time.zone.now)
    end
  end

  def password_reset_expired?
    if reset_sent_at < 2.hours.ago
      self.reset_token = nil
      self.reset_sent_at = nil
      return true
    else
      return false
    end  
  end

  def send_password_reset_email
    PasswordResetEmail.password_reset(self)
  end

  def is_editable_by? user
    user and (user.id == id or user.super_admin)
  end

  def self.valid_password password
    password.length >= 8 and password.match(/[a-zA-Z]/) and password.match(/\d/)
  end

  def is_local?
    !password_hash.nil?
  end

  def website_url
    website
  end

  def social_github_url
    "https://github.com/#{social_github}"
  end

  def social_google_url
    "https://plus.google.com/+#{social_google}"
  end

  def social_linkedin_url
    "https://www.linkedin.com/in/#{social_linkedin}"
  end

  def social_twitter_url
    "https://twitter.com/#{social_twitter}"
  end

  # ELASTICSEARCH

  include Application::IndexAdapter::Elasticsearch
  include Application::Index

  after_save do
    destroy_index! if index_exists?
    create_index!
  end

  before_destroy do
    destroy_index!
  end

  def index_identity
    {
        index: index_name,
        type: 'users',
        id: id
    }
  end

  def index_body
    body = prepare_index_body do
      serializable_hash.merge({
        'competencies' => competencies.map(&:name),
        'positions'    => position ? [ position.title ] : []
      })
    end
    body
  end

  def give_badge badge
    badges << badge
    alter_points :other, badge.points
    Notifications.badge_received(badge, self)
  end

  def alter_points(type, diff)
    case
    when type == :ideas
      self.idea_points    = [0, idea_points    + diff].max
    when type == :projects
      self.project_points = [0, project_points + diff].max
    else
      self.other_points   = [0, other_points   + diff].max
    end
    self.save

    if organization
      case
      when type == :ideas
        organization.idea_points    = [0, organization.idea_points    + diff].max
      when type == :projects
        organization.project_points = [0, organization.project_points + diff].max
      else
        organization.other_points   = [0, organization.other_points   + diff].max
      end
      organization.save
    end
  end

  def is_showcasing_badge? badge
    user_badge = user_badges.find_by_badge_id badge.id

    if user_badge && user_badge.showcase
      return true
    else
      return false
    end
  end

  def is_viewable_by? user
    user && !hidden
  end

  def is_viewable_by? user
    if user.nil?
      false
    elsif self == user || user.super_admin
      true
    else
      !hidden
    end
  end

  def self.send_activity_summary
    users = User.where(activity_summary: true)
    users.each do |u|
      ActivitySummary.send_summary(u)
    end
  end

end

#http://localhost:3000/password_resets/9pW38E3Pl2FRDDf0YWdcNA/edit?email=a%40ucla.edu
#https://localhost:8080/password_resets/9pW38E3Pl2FRDDf0YWdcNA/edit?email=a%40ucla.edu
