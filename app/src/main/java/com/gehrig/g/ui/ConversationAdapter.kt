package com.gehrig.g.ui

import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.gehrig.g.R
import com.gehrig.g.model.ConversationMessage
import com.gehrig.g.model.Role

class ConversationAdapter(
    private val messages: MutableList<ConversationMessage> = mutableListOf()
) : RecyclerView.Adapter<ConversationAdapter.MessageViewHolder>() {

    fun addMessage(message: ConversationMessage) {
        messages.add(message)
        notifyItemInserted(messages.size - 1)
    }

    fun setMessages(newMessages: List<ConversationMessage>) {
        messages.clear()
        messages.addAll(newMessages)
        notifyDataSetChanged()
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): MessageViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_message, parent, false)
        return MessageViewHolder(view)
    }

    override fun onBindViewHolder(holder: MessageViewHolder, position: Int) {
        holder.bind(messages[position])
    }

    override fun getItemCount() = messages.size

    class MessageViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        private val bubble: LinearLayout = itemView.findViewById(R.id.messageBubble)
        private val senderLabel: TextView = itemView.findViewById(R.id.senderLabel)
        private val messageText: TextView = itemView.findViewById(R.id.messageText)
        private val actionLabel: TextView = itemView.findViewById(R.id.actionLabel)

        fun bind(message: ConversationMessage) {
            val context = itemView.context
            val params = bubble.layoutParams as FrameLayout.LayoutParams

            when (message.role) {
                Role.USER -> {
                    params.gravity = Gravity.END
                    bubble.setBackgroundColor(context.getColor(R.color.g_user_bubble))
                    senderLabel.text = "You"
                    senderLabel.setTextColor(context.getColor(R.color.g_accent))
                }
                Role.ASSISTANT -> {
                    params.gravity = Gravity.START
                    bubble.setBackgroundColor(context.getColor(R.color.g_assistant_bubble))
                    senderLabel.text = "G"
                    senderLabel.setTextColor(context.getColor(R.color.g_accent))
                }
            }
            bubble.layoutParams = params

            messageText.text = message.text

            if (message.action != null) {
                actionLabel.visibility = View.VISIBLE
                actionLabel.text = message.action
            } else {
                actionLabel.visibility = View.GONE
            }
        }
    }
}
