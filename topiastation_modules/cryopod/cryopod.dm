#define AHELP_FIRST_MESSAGE "Please adminhelp before leaving the round, even if there are no administrators online!"

/*
 * Cryogenic refrigeration unit. Basically a despawner.
 * Stealing a lot of concepts/code from sleepers due to massive laziness.
 * The despawn tick will only fire if it's been more than time_till_despawned ticks
 * since time_entered, which is world.time when the occupant moves in.
 * ~ Zuhayr
 */
GLOBAL_LIST_EMPTY(cryopod_computers)

//Main cryopod console.

/obj/machinery/computer/cryopod
	name = "cryogenic oversight console"
	desc = "An interface between crew and the cryogenic storage oversight systems."
	icon = 'topiastation_modules/icons/obj/computer.dmi'
	icon_state = "wallconsole"
	icon_screen = "wallconsole_cryo"
	icon_keyboard = null
	// circuit = /obj/item/circuitboard/cryopodcontrol
	density = FALSE
	interaction_flags_machine = INTERACT_MACHINE_OFFLINE
	req_one_access = list(ACCESS_COMMAND, ACCESS_ARMORY) // Heads of staff or the warden can go here to claim recover items from their department that people went were cryodormed with.
	var/mode = null

	// Used for logging people entering cryosleep and important items they are carrying.
	var/list/frozen_crew = list()
	var/list/frozen_items = list()

	var/storage_type = "crewmembers"
	var/storage_name = "Cryogenic Oversight Control"
	var/allow_items = TRUE

/obj/machinery/computer/cryopod/old
	name = "cryogenic oversight console"
	desc = "An interface between crew and the cryogenic storage oversight systems. This one appears to  be strugggling to catch up with the more modren cryogenic storage system."
	icon = 'topiastation_modules/icons/obj/computer.dmi'
	icon_state = "wallconsole_old"
	icon_screen = "wallconsole_old_cryo"

/obj/machinery/computer/cryopod/Initialize(mapload)
	. = ..()
	GLOB.cryopod_computers += src

/obj/machinery/computer/cryopod/Destroy()
	GLOB.cryopod_computers -= src
	return ..()

/obj/machinery/computer/cryopod/ui_interact(mob/user, datum/tgui/ui)
	if(machine_stat & (NOPOWER|BROKEN))
		return

	add_fingerprint(user)

	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "CryopodConsole", name)
		ui.open()

/obj/machinery/computer/cryopod/ui_data(mob/user)
	var/list/data = list()
	data["allow_items"] = allow_items
	data["frozen_crew"] = frozen_crew
	data["frozen_items"] = list()

	if(allow_items)
		data["frozen_items"] = frozen_items

	var/obj/item/card/id/id_card
	var/datum/bank_account/current_user
	if(isliving(user))
		var/mob/living/person = user
		id_card = person.get_idcard()
	if(id_card?.registered_account)
		current_user = id_card.registered_account
	if(current_user)
		data["account_name"] = current_user.account_holder

	return data

/obj/machinery/computer/cryopod/ui_act(action, params)
	. = ..()
	if(.)
		return

	var/mob/user = usr

	add_fingerprint(user)

	switch(action)
		if("one_item")
			if(!allowed(user))
				to_chat(user, "<span class='warning'>Access Denied.</span>")
				return

			if(!allow_items) return

			if(!params["item"])
				return

			var/obj/item/item = frozen_items[text2num(params["item"])]
			if(!item)
				to_chat(user, "<span class='notice'>[item] is no longer in storage.</span>")
				return

			visible_message("<span class='notice'>[src] beeps happily as it disgorges [item].</span>")
			item.forceMove(get_turf(src))
			frozen_items -= item

		if("all_items")
			if(!allowed(user))
				to_chat(user, "<span class='warning'>Access Denied.</span>")
				return

			if(!allow_items) return

			visible_message("<span class='notice'>[src] beeps happily as it disgorges the desired objects.</span>")

			for(var/obj/item/item in frozen_items)
				item.forceMove(get_turf(src))
				frozen_items -= item

	return TRUE

// Cryopods themselves.
/obj/machinery/cryopod
	name = "cryogenic freezer"
	desc = "Keeps crew frozen in cryostasis until they are needed in order to cut down on supply usage."
	icon = 'topiastation_modules/icons/obj/machines/cryopod.dmi'
	icon_state = "cryopod-open"
	density = TRUE
	anchored = TRUE
	state_open = TRUE

	var/open_state = "cryopod-open"
	var/close_state = "cryopod"

	var/on_store_message = "has entered long-term storage."
	var/on_store_name = "Cryogenic Oversight"

	var/open_sound = 'sound/machines/podopen.ogg'
	var/close_sound = 'sound/machines/podclose.ogg'

	/// Time until despawn when a mob enters a cryopod. You cannot other people in pods unless they're catatonic.
	var/time_till_despawn = 30 SECONDS
	/// Cooldown for when it's now safe to try an despawn the player.
	COOLDOWN_DECLARE(despawn_world_time)

	var/obj/machinery/computer/cryopod/control_computer
	COOLDOWN_DECLARE(last_no_computer_message)

/obj/machinery/cryopod/Initialize(mapload)
	..()
	return INITIALIZE_HINT_LATELOAD //Gotta populate the cryopod computer GLOB first

/obj/machinery/cryopod/LateInitialize()
	update_icon()
	find_control_computer()

// This is not a good situation
/obj/machinery/cryopod/Destroy()
	control_computer = null
	return ..()

/obj/machinery/cryopod/proc/find_control_computer(urgent = FALSE)
	for(var/cryo_console as anything in GLOB.cryopod_computers)
		var/obj/machinery/computer/cryopod/console = cryo_console
		if(get_area(console) == get_area(src))
			control_computer = console
			break

	// Don't send messages unless we *need* the computer, and less than five minutes have passed since last time we messaged
	if(!control_computer && urgent && COOLDOWN_FINISHED(src, last_no_computer_message))
		COOLDOWN_START(src, last_no_computer_message, 5 MINUTES)
		log_admin("Cryopod in [get_area(src)] could not find control computer!")
		message_admins("Cryopod in [get_area(src)] could not find control computer!")
		last_no_computer_message = world.time

	return control_computer != null

/obj/machinery/cryopod/JoinPlayerHere(mob/M, buckle)
	close_machine(M, TRUE)

/obj/machinery/cryopod/latejoin/Initialize()
	. = ..()
	new /obj/effect/landmark/latejoin(src)

/obj/machinery/cryopod/latejoin/Destroy()
	SSjob.latejoin_trackers -= src
	. = ..()

/obj/machinery/cryopod/close_machine(atom/movable/target, exiting = FALSE)
	if(!control_computer)
		find_control_computer(TRUE)
	if((isnull(target) || isliving(target)) && state_open && !panel_open)
		..(target)
		if(exiting && istype(target, /mob/living/carbon))
			var/mob/living/carbon/podded = target
			apply_effects_to_mob(podded)
			icon_state = close_state
			playsound(src, 'sound/machines/hiss.ogg', 30, 1)
			return
		var/mob/living/mob_occupant = occupant
		if(mob_occupant && mob_occupant.stat != DEAD)
			to_chat(occupant, "<span class='notice'><b>You feel cool air surround you. You go numb as your senses turn inward.</b></span>")

		COOLDOWN_START(src, despawn_world_time, time_till_despawn)
	icon_state = close_state
	if(close_sound)
		playsound(src, close_sound, 40)

/obj/machinery/cryopod/proc/apply_effects_to_mob(mob/living/carbon/sleepyhead)
	sleepyhead.SetSleeping(50)
	to_chat(sleepyhead, "<span class='boldnotice'>You begin to wake from cryosleep...</span>")

/obj/machinery/cryopod/open_machine()
	..()
	icon_state = open_state
	density = TRUE
	name = initial(name)
	if(open_sound)
		playsound(src, open_sound, 40)

/obj/machinery/cryopod/container_resist_act(mob/living/user)
	visible_message("<span class='notice'>[occupant] emerges from [src]!</span>",
		"<span class='notice'>You climb out of [src]!</span>")
	open_machine()

/obj/machinery/cryopod/relaymove(mob/user)
	container_resist_act(user)

/obj/machinery/cryopod/process()
	if(!occupant)
		return

	var/mob/living/mob_occupant = occupant
	if(mob_occupant.stat == DEAD)
		open_machine()

	if(!mob_occupant.client && COOLDOWN_FINISHED(src, despawn_world_time))
		if(!control_computer)
			find_control_computer(urgent = TRUE)

		despawn_occupant()

/obj/machinery/cryopod/proc/handle_objectives()
	var/mob/living/mob_occupant = occupant
	// Update any existing objectives involving this mob.
	for(var/datum/objective/objective in GLOB.objectives)
		// We don't want revs to get objectives that aren't for heads of staff. Letting
		// them win or lose based on cryo is silly so we remove the objective.
		if(istype(objective,/datum/objective/mutiny) && objective.target == mob_occupant.mind)
			objective.team.objectives -= objective
			qdel(objective)
			for(var/datum/mind/mind in objective.team.members)
				to_chat(mind.current, "<BR><span class='userdanger'>Your target is no longer within reach. Objective removed!</span>")
				mind.announce_objectives()
		else if(objective.target && istype(objective.target, /datum/mind))
			if(objective.target == mob_occupant.mind)
				var/old_target = objective.target
				objective.target = null
				if(!objective)
					return
				objective.find_target()
				if(!objective.target && objective.owner)
					to_chat(objective.owner.current, "<BR><span class='userdanger'>Your target is no longer within reach. Objective removed!</span>")
					for(var/datum/antagonist/antag in objective.owner.antag_datums)
						antag.objectives -= objective
				if (!objective.team)
					objective.update_explanation_text()
					objective.owner.announce_objectives()
					to_chat(objective.owner.current, "<BR><span class='userdanger'>You get the feeling your target is no longer within reach. Time for Plan [pick("A","B","C","D","X","Y","Z")]. Objectives updated!</span>")
				else
					var/list/objectivestoupdate
					for(var/datum/mind/objective_owner in objective.get_owners())
						to_chat(objective_owner.current, "<BR><span class='userdanger'>You get the feeling your target is no longer within reach. Time for Plan [pick("A","B","C","D","X","Y","Z")]. Objectives updated!</span>")
						for(var/datum/objective/update_target_objective in objective_owner.get_all_objectives())
							LAZYADD(objectivestoupdate, update_target_objective)
					objectivestoupdate += objective.team.objectives
					for(var/datum/objective/update_objective in objectivestoupdate)
						if(update_objective.target != old_target || !istype(update_objective,objective.type))
							continue
						update_objective.target = objective.target
						update_objective.update_explanation_text()
						to_chat(objective.owner.current, "<BR><span class='userdanger'>You get the feeling your target is no longer within reach. Time for Plan [pick("A","B","C","D","X","Y","Z")]. Objectives updated!</span>")
						update_objective.owner.announce_objectives()
				qdel(objective)

/obj/machinery/cryopod/proc/should_preserve_item(obj/item/item)
	for(var/datum/objective_item/steal/possible_item in GLOB.possible_items)
		if(istype(item, possible_item.targetitem))
			return TRUE
	return FALSE

// This function can not be undone; do not call this unless you are sure
/obj/machinery/cryopod/proc/despawn_occupant()
	var/mob/living/mob_occupant = occupant
	var/list/crew_member = list()

	crew_member["name"] = mob_occupant.real_name

	if(mob_occupant.mind && mob_occupant.mind.assigned_role)
		// Handle job slot/tater cleanup.
		var/job = mob_occupant.mind.assigned_role.title
		crew_member["job"] = job
		SSjob.FreeRole(job)
		if(LAZYLEN(mob_occupant.mind.objectives))
			mob_occupant.mind.objectives.Cut()
			mob_occupant.mind.special_role = null
	else
		crew_member["job"] = "N/A"

	// Delete them from datacore.
	var/announce_rank = null
	for(var/datum/data/record/medical_record as anything in GLOB.data_core.medical)
		if(medical_record.fields["name"] == mob_occupant.real_name)
			qdel(medical_record)
	for(var/datum/data/record/security_record as anything in GLOB.data_core.security)
		if(security_record.fields["name"] == mob_occupant.real_name)
			qdel(security_record)
	for(var/datum/data/record/general_record as anything in GLOB.data_core.general)
		if(general_record.fields["name"] == mob_occupant.real_name)
			announce_rank = general_record.fields["rank"]
			qdel(general_record)

	control_computer?.frozen_crew += list(crew_member)

	// Make an announcement and log the person entering storage.
	if(GLOB.announcement_systems.len)
		var/obj/machinery/announcement_system/announcer = pick(GLOB.announcement_systems)
		announcer.announce("CRYOSTORAGE", mob_occupant.real_name, announce_rank, list())

	visible_message("<span class='notice'>[src] hums and hisses as it moves [mob_occupant.real_name] into storage.</span>")

	for(var/obj/item/item in mob_occupant.get_all_contents())
		if(item.loc.loc && (item.loc.loc == loc || item.loc.loc == control_computer))
			continue // means we already moved whatever this thing was in
			// I'm a professional, okay

		if(!should_preserve_item(item))
			continue

		if(control_computer && control_computer.allow_items)
			control_computer.frozen_items += item
			mob_occupant.transferItemToLoc(item, control_computer, TRUE)
		else
			mob_occupant.transferItemToLoc(item, loc, TRUE)

	var/list/contents = mob_occupant.get_all_contents()
	QDEL_LIST(contents)

	// Ghost and delete the mob.
	if(!mob_occupant.get_ghost(TRUE))
		if(world.time < 15 MINUTES) // before the 15 minute mark
			mob_occupant.ghostize(FALSE) // Players despawned too early may not re-enter the game
		else
			mob_occupant.ghostize(TRUE)

	handle_objectives()
	QDEL_NULL(occupant)
	open_machine()
	name = initial(name)

/obj/machinery/cryopod/MouseDrop_T(mob/living/target, mob/user)
	if(!istype(target) || !can_interact(user) || !target.Adjacent(user) || !ismob(target) || isanimal(target) || !istype(user.loc, /turf) || target.buckled)
		return

	if(occupant)
		to_chat(user, "<span class='notice'>[src] is already occupied!</span>")
		return

	if(target.stat == DEAD)
		to_chat(user, "<span class='notice'>Dead people can not be put into cryo.</span>")
		return

	if(target.key && user != target)
		if(iscyborg(target))
			to_chat(user, "<span class='danger'>You can't put [target] into [src]. [target.p_theyre(capitalized = TRUE)] online.</span>")
		else
			to_chat(user, "<span class='danger'>You can't put [target] into [src]. [target.p_theyre(capitalized = TRUE)] conscious.</span>")
		return

	if(target == user && (tgalert(target, "Would you like to enter cryosleep?", "Enter Cryopod?", "Yes", "No") != "Yes"))
		return

	if(target == user)
		var/datum/antagonist/antag = target.mind.has_antag_datum(/datum/antagonist)

		var/datum/job/target_job = SSjob.GetJob(target.mind.assigned_role)

		if(target_job && target_job.req_admin_notify)
			tgalert(target, "You're an important role! [AHELP_FIRST_MESSAGE]")
		if(antag)
			tgalert(target, "You're \a [antag.name]! [AHELP_FIRST_MESSAGE]")

	if(!istype(target) || !can_interact(user) || !target.Adjacent(user) || !ismob(target) || isanimal(target) || !istype(user.loc, /turf) || target.buckled)
		return
		// rerun the checks in case of shenanigans

	if(occupant)
		to_chat(user, "<span class='notice'>[src] is already occupied!</span>")
		return

	if(target == user)
		visible_message("<span class='infoplain'>[user] starts climbing into the cryo pod.</span>")
	else
		visible_message("<span class='infoplain'>[user] starts putting [target] into the cryo pod.</span>")

	to_chat(target, "<span class='warning'><b>If you ghost, log out or close your client now, your character will shortly be permanently removed from the round.</b></span>")

	log_admin("[key_name(target)] entered a stasis pod.")
	message_admins("[key_name_admin(target)] entered a stasis pod. [ADMIN_JMP(src)]")
	add_fingerprint(target)

	close_machine(target)
	name = "[name] ([target.name])"

// Attacks/effects.
/obj/machinery/cryopod/blob_act()
	return // Sorta gamey, but we don't really want these to be destroyed.

/obj/machinery/cryopod/poor
	name = "low quality cryogenic freezer"
	desc = "Keeps crew frozen in cryostasis until they are needed in order to cut down on supply usage. This one seems cheaply made."

/obj/machinery/cryopod/poor/apply_effects_to_mob(mob/living/carbon/sleepyhead)
	sleepyhead.SetSleeping(50)
	sleepyhead.set_disgust(60)
	sleepyhead.set_nutrition(160)
	to_chat(sleepyhead, "<span class='bolddanger'>A very bad headache wakes you up from cryosleep...</span>")

#undef AHELP_FIRST_MESSAGE
