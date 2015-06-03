class GroupsController < ApplicationController
  respond_to :json

  def index
    groups = Group.where("name like ?", "%#{params[:q]}%")
    render json: groups.as_json(only: [:id, :name])
  end
end