module Sidekiq
  module Monitor
    class Cleaner
      @ignored_queues = []

      class << self
        attr_reader :ignored_queues

        def add_ignored_queue(queue)
          @ignored_queues << queue.to_s
          @ignored_queues.uniq!
        end
      end

      # Cleans up records that are no longer in sync with Sidekiq's records
      def clean
        clean_queued
        clean_running
      end

      private

      def clean_queued
        Sidekiq.redis do |conn|
          queues = conn.smembers('queues')
          queued_jids = []
          queues.each do |queue|
            workers = conn.lrange("queue:#{queue}", 0, -1)
            workers.each do |worker|
              worker = Sidekiq.load_json(worker)
              queued_jids << worker['jid']
            end
          end

          Sidekiq::Monitor::Job.where(status: 'queued').each do |job|
            if !queued_jids.include?(job.jid) && !is_ignored_queue?(job.queue)
              job.update_attributes(
                finished_at: DateTime.now,
              )
            end
          end
        end
      end

      def clean_running
        Sidekiq.redis do |conn|
          workers = conn.smembers('workers')
          busy_jids = []
          workers.each do |worker|
            worker = conn.get("worker:#{worker}")
            next if worker.blank?
            worker = Sidekiq.load_json(worker)
            busy_jids << worker['payload']['jid']
          end

          Sidekiq::Monitor::Job.where(status: 'running').each do |job|
            if !busy_jids.include?(job.jid) && !is_ignored_queue?(job.queue)
              job.update_attributes(
                finished_at: DateTime.now,
              )
            end
          end
        end
      end

      def is_ignored_queue?(queue)
        self.class.ignored_queues.include?(queue)
      end
    end
  end
end
