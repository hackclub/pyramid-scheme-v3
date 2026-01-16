# frozen_string_literal: true

module Admin
  class UsersController < BaseController
    def index
      @pagy, @users = pagy(
        User.search(params[:q]).order(created_at: :desc),
        limit: 25
      )

      respond_to do |format|
        format.html
        format.text do
          users = User.search(params[:q]).order(created_at: :desc)
          render plain: users.map { |u|
            "#{u.display_name} | #{u.email} | #{u.total_shards} shards | #{u.role.humanize}"
          }.join("\n")
        end
      end
    end

    def show
      @user = User.find(params[:id])
      @referrals = @user.referrals_given.includes(:campaign).order(created_at: :desc).limit(20)
      @posters = @user.posters.includes(:campaign).order(created_at: :desc).limit(20)
      @transactions = @user.shard_transactions.recent.limit(20)
      @orders = @user.shop_orders.includes(:shop_item).recent.limit(20)
      @referral_logs = @user.referral_code.present? ? ReferralCodeLog.for_code(@user.referral_code).recent.limit(25) : []
    end

    def edit
      @user = User.find(params[:id])
    end

    def update
      @user = User.find(params[:id])

      if @user.update(user_params)
        redirect_to admin_user_path(@user), notice: "User updated successfully."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def grant_shards
      @user = User.find(params[:id])
      amount = params[:amount].to_i
      description = params[:description]

      if amount == 0
        return redirect_to admin_user_path(@user), alert: "Amount cannot be zero."
      end

      # Allow negative grants, but cap at user's current balance (can't go below 0)
      if amount < 0 && amount.abs > @user.total_shards
        amount = -@user.total_shards
        if amount == 0
          return redirect_to admin_user_path(@user), alert: "User has no shards to deduct."
        end
      end

      @user.credit_shards!(
        amount,
        transaction_type: "admin_grant",
        description: description.presence || (amount > 0 ? "Admin grant" : "Admin deduction")
      )

      if amount > 0
        redirect_to admin_user_path(@user), notice: "Granted #{amount} shards to #{@user.display_name}."
      else
        redirect_to admin_user_path(@user), notice: "Deducted #{amount.abs} shards from #{@user.display_name}."
      end
    end

    def debit_shards
      @user = User.find(params[:id])
      amount = params[:amount].to_i
      description = params[:description]

      if amount <= 0
        return redirect_to admin_user_path(@user), alert: "Amount must be positive."
      end

      if amount > @user.total_shards
        return redirect_to admin_user_path(@user), alert: "User only has #{@user.total_shards} shards."
      end

      @user.debit_shards!(
        amount,
        transaction_type: "admin_debit",
        description: description.presence || "Admin debit"
      )

      redirect_to admin_user_path(@user), notice: "Debited #{amount} shards from #{@user.display_name}."
    end

    def ban
      @user = User.find(params[:id])
      @user.ban!(
        reason: params[:banned_reason],
        internal_reason: params[:internal_ban_reason]
      )
      redirect_to admin_user_path(@user), notice: "User has been banned."
    end

    def unban
      @user = User.find(params[:id])
      @user.unban!
      redirect_to admin_user_path(@user), notice: "User has been unbanned."
    end

    def promote_to_admin
      @user = User.find(params[:id])

      if @user.admin?
        redirect_to admin_user_path(@user), alert: "User is already an admin."
        return
      end

      @user.update!(role: :admin)

      Rails.logger.info("Admin #{current_user.id} (#{current_user.slack_id}) promoted user #{@user.id} (#{@user.display_name}) to admin")

      redirect_to admin_user_path(@user), notice: "#{@user.display_name} has been promoted to admin."
    end

    def demote_from_admin
      @user = User.find(params[:id])

      if @user == current_user
        redirect_to admin_user_path(@user), alert: "You cannot demote yourself."
        return
      end

      unless @user.admin?
        redirect_to admin_user_path(@user), alert: "User is not an admin."
        return
      end

      @user.update!(role: :user)

      Rails.logger.info("Admin #{current_user.id} (#{current_user.slack_id}) demoted admin #{@user.id} (#{@user.display_name}) to user")

      redirect_to admin_user_path(@user), notice: "#{@user.display_name} has been demoted from admin."
    end

    def wipe_data
      @user = User.find(params[:id])

      referrals_count = @user.referrals_given.count
      posters_count = @user.posters.count

      # Destroy all referrals given by this user
      @user.referrals_given.destroy_all

      # Destroy all posters by this user
      @user.posters.destroy_all

      # Reset counts
      @user.update!(referral_count: 0, poster_count: 0)

      redirect_to admin_user_path(@user), notice: "Wiped #{referrals_count} referrals and #{posters_count} posters for #{@user.display_name}."
    end

    def destroy
      @user = User.find(params[:id])

      # Prevent deleting yourself
      if @user == current_user
        redirect_to admin_user_path(@user), alert: "You cannot delete your own account."
        return
      end

      # Prevent deleting other admins (safety measure)
      if @user.admin?
        redirect_to admin_user_path(@user), alert: "Cannot delete admin users. Demote them first."
        return
      end

      user_name = @user.display_name
      user_email = @user.email

      # Destroy all associated data first
      @user.referrals_given.destroy_all
      @user.posters.destroy_all
      @user.shard_transactions.destroy_all
      @user.shop_orders.destroy_all
      @user.user_emblems.destroy_all

      # Now destroy the user
      @user.destroy!

      Rails.logger.info("Admin #{current_user.id} (#{current_user.slack_id}) deleted user #{user_name} (#{user_email})")

      redirect_to admin_users_path, notice: "User #{user_name} has been permanently deleted."
    end

    private

    def user_params
      params.require(:user).permit(:display_name, :role, :internal_notes, :leaderboard_opted_out)
    end
  end
end
